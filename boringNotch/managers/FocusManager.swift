import Foundation
import Combine
import Defaults

/// Tracks the active macOS Focus mode by reading the DoNotDisturb database.
/// Requires the app to run without App Sandbox and to have Full Disk Access.
final class FocusManager: ObservableObject {
    static let shared = FocusManager()

    @Published var isActive: Bool = false
    @Published var modeName: String = ""
    @Published var symbolName: String = "moon.fill"
    /// False when the DoNotDisturb DB can't be read (missing Full Disk Access).
    @Published var hasAccess: Bool = true

    private let dbDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB")
    private var timer: Timer?
    private var lastIdentifier: String? = nil
    private var didInitialRead = false

    private init() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    deinit { timer?.invalidate() }

    private func poll() {
        guard let assertions = readJSON("Assertions.json") else {
            DispatchQueue.main.async { self.hasAccess = false }
            return
        }
        let identifier = Self.findString(forKey: "assertionDetailsModeIdentifier", in: assertions)

        var name = "Focus"
        var symbol = "moon.fill"
        if let id = identifier, let modes = readJSON("ModeConfigurations.json") {
            if let data = (modes["data"] as? [[String: Any]])?.first,
               let configs = data["modeConfigurations"] as? [String: Any],
               let cfg = configs[id] as? [String: Any],
               let mode = cfg["mode"] as? [String: Any] {
                name = (mode["name"] as? String) ?? name
                symbol = (mode["symbolImageName"] as? String) ?? symbol
            } else if id.contains("donotdisturb") {
                name = "Do Not Disturb"
            }
        }

        DispatchQueue.main.async {
            self.hasAccess = true
            let changed = identifier != self.lastIdentifier
            self.lastIdentifier = identifier
            self.isActive = identifier != nil
            self.modeName = name
            self.symbolName = symbol

            // Don't announce on first read (app launch) — only on real changes.
            if changed && self.didInitialRead && Defaults[.showFocusNotifications] {
                BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .focus)
            }
            self.didInitialRead = true
        }
    }

    private func readJSON(_ file: String) -> [String: Any]? {
        let url = dbDir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    /// Depth-first search for a string value under `key` anywhere in a JSON tree.
    private static func findString(forKey key: String, in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let v = dict[key] as? String { return v }
            for v in dict.values { if let r = findString(forKey: key, in: v) { return r } }
        } else if let arr = node as? [Any] {
            for v in arr { if let r = findString(forKey: key, in: v) { return r } }
        }
        return nil
    }
}
