import Foundation

final class DeviceSelectionModel: ObservableObject {
    @Published var selectedDevice: RazerDeviceSelection = .keyboard
    @Published var keyboardConnected = false
    @Published var mouseConnected = false

    private let deathAdderMonitor = DeathAdderConnectionMonitor()
    private weak var keyboardModel: MacroAppModel?
    private var pollTimer: Timer?

    var availableDevices: [RazerDeviceSelection] {
        var devices: [RazerDeviceSelection] = []
        if keyboardConnected {
            devices.append(.keyboard)
        }
        if mouseConnected {
            devices.append(.mouse)
        }
        return devices
    }

    var selectedDeviceTitle: String {
        if selectedDevice == .keyboard {
            return keyboardConnected ? RazerDeviceSelection.keyboard.title : RazerDeviceSelection.keyboard.disconnectedTitle
        }
        return mouseConnected ? RazerDeviceSelection.mouse.title : RazerDeviceSelection.mouse.disconnectedTitle
    }

    var statusTitle: String {
        availableDevices.isEmpty ? "Razer device not detected" : selectedDeviceTitle
    }

    func start(keyboardModel: MacroAppModel) {
        self.keyboardModel = keyboardModel
        refreshConnectionState()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshConnectionState()
        }
    }

    func shutdown() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func refreshConnectionState() {
        keyboardConnected = keyboardModel?.deviceConnected ?? false
        mouseConnected = deathAdderMonitor.isConnected()

        let available = availableDevices
        guard !available.isEmpty else {
            selectedDevice = .keyboard
            return
        }

        if !available.contains(selectedDevice) {
            selectedDevice = available[0]
        }
    }
}
