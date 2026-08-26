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

    private override init() {
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    deinit {
        connectNotification?.unregister()
        disconnectNotifications.values.forEach { $0.unregister() }
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
