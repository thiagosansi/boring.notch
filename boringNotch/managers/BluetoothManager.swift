import Foundation
import IOBluetooth
import Combine
import Defaults

/// Watches Bluetooth connect/disconnect events (AirPods, headphones, keyboards, mice…)
/// and shows a short live activity in the closed notch, like the battery notification.
final class BluetoothManager: NSObject, ObservableObject {
    static let shared = BluetoothManager()

    @Published var deviceName: String = ""
    @Published var isConnected: Bool = false
    @Published var iconName: String = "headphones"

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var pollTimer: Timer?
    private var connectedAddresses: Set<String> = []
    private var lastAnnouncedAt: Date = .distantPast
    private var lastKey: String = ""

    private override init() {
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
        // Seed current state silently, then poll: connect notifications don't fire reliably
        // for every device (e.g. AirPods that auto-connect), so we also diff isConnected().
        connectedAddresses = Self.currentlyConnectedAddresses()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    deinit {
        pollTimer?.invalidate()
        connectNotification?.unregister()
        disconnectNotifications.values.forEach { $0.unregister() }
    }

    private static func currentlyConnectedAddresses() -> Set<String> {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return Set(devices.filter { $0.isConnected() }.compactMap { $0.addressString })
    }

    private func poll() {
        let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        let now = Set(devices.filter { $0.isConnected() }.compactMap { $0.addressString })
        guard now != connectedAddresses else { return }
        let appeared = now.subtracting(connectedAddresses)
        let vanished = connectedAddresses.subtracting(now)
        connectedAddresses = now
        for d in devices {
            guard let addr = d.addressString else { continue }
            if appeared.contains(addr) { announce(d, connected: true) }
            else if vanished.contains(addr) { announce(d, connected: false) }
        }
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let key = device.addressString ?? UUID().uuidString
        disconnectNotifications[key]?.unregister()
        disconnectNotifications[key] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
        announce(device, connected: true)
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        notification.unregister()
        if let key = device.addressString { disconnectNotifications[key] = nil }
        announce(device, connected: false)
    }

    private func announce(_ device: IOBluetoothDevice, connected: Bool) {
        guard Defaults[.showBluetoothNotifications] else { return }
        // Notification + poll can both fire for the same event; collapse duplicates.
        let key = "\(device.addressString ?? "")-\(connected)"
        if key == lastKey, Date().timeIntervalSince(lastAnnouncedAt) < 4 { return }
        lastKey = key; lastAnnouncedAt = Date()
        if connected { connectedAddresses.insert(device.addressString ?? "") } else { connectedAddresses.remove(device.addressString ?? "") }
        let name = device.name ?? "Bluetooth"
        let icon = Self.icon(for: device)
        Task { @MainActor in
            self.deviceName = name
            self.isConnected = connected
            self.iconName = icon
            BoringViewCoordinator.shared.toggleExpandingView(status: true, type: .bluetooth)
        }
    }

    /// Picks an SF Symbol from the device name / Bluetooth class of device.
    private static func icon(for device: IOBluetoothDevice) -> String {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return "airpodsmax" }
        if name.contains("airpods pro") { return "airpodspro" }
        if name.contains("airpods 4") { return "airpods.gen4" }
        if name.contains("airpods 3") { return "airpods.gen3" }
        if name.contains("airpods") { return "airpods" }
        if name.contains("beats") { return "beats.headphones" }

        let major = device.deviceClassMajor
        let minor = device.deviceClassMinor
        switch major {
        case 0x04: // Audio/Video
            switch minor {
            case 0x01: return "headset"        // wearable headset
            case 0x05: return "hifispeaker"    // loudspeaker
            default:   return "headphones"
            }
        case 0x05: // Peripheral
            if minor & 0x10 != 0 { return "keyboard" }
            if minor & 0x20 != 0 { return "computermouse" }
            return "gamecontroller"
        case 0x02: return "iphone"            // Phone
        case 0x01: return "laptopcomputer"    // Computer
        case 0x07: return "applewatch"        // Wearable
        default:   return "wave.3.right"
        }
    }
}
