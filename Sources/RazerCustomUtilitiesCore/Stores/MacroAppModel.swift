import AppKit
import Foundation

public final class MacroAppModel: ObservableObject {
    @Published public var macroModeEnabled = false
    @Published public var deviceConnected = false
    @Published var inputMonitoringPermissionState: HIDPermissionState = .unknown
    @Published var accessibilityPermissionState: HIDPermissionState = .unknown
    @Published var activeKeyCodes = Set<UInt8>()
    @Published var developerModeEnabled = false
    @Published var developerEvents: [String] = []
    @Published public var capsLockLEDFixEnabled: Bool {
        didSet {
            UserDefaults.standard.set(capsLockLEDFixEnabled, forKey: Self.capsLockLEDFixDefaultsKey)
            updateCapsLockLEDAvailability()
        }
    }
    @Published var keySwapRules: [KeySwapRule] = [] {
        didSet {
            saveKeySwapRules()
            updateKeySwapAvailability()
        }
    }
    @Published var assignedActions: [UInt8: MacroAssignment] = [:] {
        didSet {
            saveAssignments()
        }
    }

    private let service = RazerHIDService()
    private let rawKeyboardMonitor = RawKeyboardEventMonitor()
    private let keySwapEventTap = KeySwapEventTap()
    private let capsLockLEDController = CapsLockLEDController()
    private var devicePollTimer: Timer?
    private var permissionPollTimer: Timer?
    private var shortcutRecorder: ShortcutRecorderPanelController?
    private var keyCapturePanel: KeyCapturePanelController?
    private var wantsMacroModeEnabled = true
    private var hasShownPermissionRecoveryNotice = false
    private let assignmentsDefaultsKey = "MacroAssignments"
    private let keySwapRulesDefaultsKey = "KeySwapRules"
    private static let capsLockLEDFixDefaultsKey = "CapsLockLEDFixEnabled"
    private let developerEventLimit = 60

    let developerVendorID = "0x1532"
    let developerProductID = "0x0293"

    var deviceStatusLabel: String {
        deviceConnected ? "BlackWidow V4 X" : "Razer keyboard not found"
    }

    var permissionStatusLabel: String {
        let missingPermissions = missingPermissionNames()
        if missingPermissions.isEmpty {
            return "Permissions granted"
        }

        return "Permission required: \(missingPermissions.joined(separator: ", "))"
    }

    var permissionState: HIDPermissionState {
        requiredPermissionsGranted ? .granted : .unknown
    }

    public init() {
        capsLockLEDFixEnabled = UserDefaults.standard.object(forKey: Self.capsLockLEDFixDefaultsKey) as? Bool ?? true
        assignedActions = Self.loadAssignments()
        keySwapRules = Self.loadKeySwapRules()

        service.onMacroEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }

        rawKeyboardMonitor.onEvent = { [weak self] event in
            self?.appendDeveloperEvent(event)
        }
    }

    public func start() {
        refreshPermissionState(requestIfNeeded: true)
        refreshDeviceConnection()
        startDevicePolling()
        updatePermissionPolling()
        setMacroModeEnabled(true)
        updateKeySwapAvailability()
    }

    public func setMacroModeEnabled(_ enabled: Bool) {
        wantsMacroModeEnabled = enabled
        refreshPermissionState(requestIfNeeded: enabled)
        guard requiredPermissionsGranted || !enabled else {
            macroModeEnabled = false
            activeKeyCodes.removeAll()
            return
        }

        do {
            if enabled {
                try service.setMacroModeEnabled(true)
                macroModeEnabled = true
                deviceConnected = true
                hasShownPermissionRecoveryNotice = false
            } else {
                try service.setMacroModeEnabled(false)
                macroModeEnabled = false
                activeKeyCodes.removeAll()
            }
        } catch {
            macroModeEnabled = false
            activeKeyCodes.removeAll()
            if enabled && requiredPermissionsGranted {
                showPermissionRecoveryNoticeIfNeeded()
            }
        }
    }

    public func shutdown() {
        devicePollTimer?.invalidate()
        devicePollTimer = nil
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
        rawKeyboardMonitor.stop()
        keySwapEventTap.stop()
        capsLockLEDController.stop()
        service.stopListening()
        activeKeyCodes.removeAll()
    }

    func assignedActionTitle(for key: MacroKey) -> String {
        assignedActions[key.id]?.displayTitle ?? "Click to assign"
    }

    func assign(_ assignment: MacroAssignment, to key: MacroKey) {
        guard deviceConnected else {
            return
        }

        assignedActions[key.id] = assignment
    }

    func beginShortcutCapture(for key: MacroKey) {
        guard deviceConnected else {
            return
        }

        shortcutRecorder?.close()

        let recorder = ShortcutRecorderPanelController(keyName: key.name)
        recorder.onSave = { [weak self] shortcut in
            self?.assign(.shortcut(shortcut), to: key)
        }
        recorder.onClose = { [weak self, weak recorder] in
            guard let recorder, self?.shortcutRecorder === recorder else {
                return
            }
            self?.shortcutRecorder = nil
        }
        shortcutRecorder = recorder
        recorder.show()
    }

    func beginOpenAppSelection(for key: MacroKey) {
        guard deviceConnected else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Select App or Script"
        panel.prompt = "Assign"
        panel.message = "Choose the app or script to run with \(key.name)."
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedFileTypes = [
            "app",
            "command",
            "tool",
            "sh",
            "zsh",
            "bash",
            "py",
            "rb",
            "pl",
            "php",
            "swift",
            "js",
            "scpt",
            "applescript",
            "workflow"
        ]

        panel.begin { [weak self] response in
            guard response == .OK,
                  let url = panel.url
            else {
                return
            }

            self?.assign(.openApp(LaunchTargetAssignment(url: url)), to: key)
        }
    }

    func beginOpenFolderSelection(for key: MacroKey) {
        guard deviceConnected else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Select Folder"
        panel.prompt = "Assign"
        panel.message = "Choose the folder to open with \(key.name)."
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        panel.begin { [weak self] response in
            guard response == .OK,
                  let url = panel.url
            else {
                return
            }

            self?.assign(.openApp(LaunchTargetAssignment(folderURL: url)), to: key)
        }
    }

    func clearAssignment(for key: MacroKey) {
        assignedActions.removeValue(forKey: key.id)
    }

    func hasAssignment(for key: MacroKey) -> Bool {
        assignedActions[key.id] != nil
    }

    func toggleDeveloperMode() {
        setDeveloperModeEnabled(!developerModeEnabled)
    }

    public func setCapsLockLEDFixEnabled(_ enabled: Bool) {
        capsLockLEDFixEnabled = enabled
    }

    func setDeveloperModeEnabled(_ enabled: Bool) {
        guard deviceConnected || !enabled else {
            return
        }

        guard developerModeEnabled != enabled else {
            return
        }

        developerModeEnabled = enabled
        if enabled {
            developerEvents.removeAll()
            appendDeveloperEvent("[dev] listening for raw key down / key up / flags changed")
            rawKeyboardMonitor.start()
        } else {
            rawKeyboardMonitor.stop()
            developerEvents.removeAll()
        }
    }

    func beginKeySwapRuleCapture() {
        guard deviceConnected else {
            return
        }

        keyCapturePanel?.close()

        let sourcePanel = KeyCapturePanelController(
            title: "Key Swapper",
            prompt: "Listening source key..."
        )
        sourcePanel.onCapture = { [weak self] source in
            self?.beginKeySwapDestinationCapture(source: source)
        }
        sourcePanel.onClose = { [weak self, weak sourcePanel] in
            guard let sourcePanel, self?.keyCapturePanel === sourcePanel else {
                return
            }
            self?.keyCapturePanel = nil
        }
        keyCapturePanel = sourcePanel
        sourcePanel.show()
    }

    func removeKeySwapRule(id: UUID) {
        guard deviceConnected else {
            return
        }

        keySwapRules.removeAll { $0.id == id }
    }

    private func startDevicePolling() {
        devicePollTimer?.invalidate()
        devicePollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshDeviceConnection()
            self?.recoverMacroModeIfPossible()
        }
    }

    private func updatePermissionPolling() {
        if requiredPermissionsGranted {
            permissionPollTimer?.invalidate()
            permissionPollTimer = nil
            return
        }

        guard permissionPollTimer == nil else {
            return
        }

        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshPermissionState(requestIfNeeded: false)
            self?.updatePermissionPolling()
            self?.recoverMacroModeIfPossible()
        }
    }

    private func refreshDeviceConnection() {
        let connected = service.isDeviceConnected()
        if deviceConnected && !connected {
            service.stopListening()
            macroModeEnabled = false
            activeKeyCodes.removeAll()
            setDeveloperModeEnabled(false)
            shortcutRecorder?.close()
            keyCapturePanel?.close()
        }
        deviceConnected = connected
        updateKeySwapAvailability()
        updateCapsLockLEDAvailability()
    }

    private func refreshPermissionState(requestIfNeeded: Bool) {
        let inputMonitoring = HIDPermissionService.checkListenAccess()
        if requestIfNeeded && inputMonitoring != .granted {
            inputMonitoringPermissionState = HIDPermissionService.requestListenAccess()
        } else {
            inputMonitoringPermissionState = inputMonitoring
        }

        let accessibility = AccessibilityPermissionService.checkAccess()
        if requestIfNeeded && accessibility != .granted {
            accessibilityPermissionState = AccessibilityPermissionService.requestAccess()
        } else {
            accessibilityPermissionState = accessibility
        }

        updatePermissionPolling()
        updateKeySwapAvailability()
        updateCapsLockLEDAvailability()
    }

    private func recoverMacroModeIfPossible() {
        guard wantsMacroModeEnabled,
              requiredPermissionsGranted,
              deviceConnected,
              !macroModeEnabled
        else {
            return
        }

        setMacroModeEnabled(true)
    }

    private func updateKeySwapAvailability() {
        if deviceConnected && requiredPermissionsGranted {
            keySwapEventTap.updateRules(keySwapRules)
        } else {
            keySwapEventTap.stop()
        }
    }

    private func updateCapsLockLEDAvailability() {
        if capsLockLEDFixEnabled && deviceConnected && requiredPermissionsGranted {
            capsLockLEDController.start()
        } else {
            capsLockLEDController.stop()
        }
    }

    private func showPermissionRecoveryNoticeIfNeeded() {
        guard !hasShownPermissionRecoveryNotice else {
            return
        }

        hasShownPermissionRecoveryNotice = true
        let alert = NSAlert()
        alert.messageText = "Restart Razer Custom Utilities"
        alert.informativeText = "Permissions were granted, but macOS has not allowed the keyboard listener to start yet. Quit and open the app again to finish enabling macro keys."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private var requiredPermissionsGranted: Bool {
        inputMonitoringPermissionState == .granted
            && accessibilityPermissionState == .granted
    }

    private func missingPermissionNames() -> [String] {
        var names: [String] = []

        if accessibilityPermissionState != .granted {
            names.append("Accessibility")
        }

        if inputMonitoringPermissionState != .granted {
            names.append("Input Monitoring")
        }

        return names
    }

    private func handle(_ event: MacroKeyEvent) {
        switch event {
        case .down(let code):
            if activeKeyCodes.insert(code).inserted {
                performAssignment(for: code)
            }
        case .up(let code):
            activeKeyCodes.remove(code)
        }
    }

    private func performAssignment(for code: UInt8) {
        guard let assignment = assignedActions[code] else {
            return
        }

        switch assignment {
        case .shortcut(let shortcut):
            ShortcutDispatcher.post(shortcut)
        case .openApp(let assignment):
            guard let assignment else {
                return
            }
            openLaunchTarget(assignment)
        case .systemAction(let action):
            SystemActionDispatcher.perform(action)
        case .showThisApp:
            NotificationCenter.default.post(name: .toggleRazerCustomUtilitiesWindow, object: nil)
        }
    }

    private func appendDeveloperEvent(_ event: String) {
        developerEvents.insert(event, at: 0)
        if developerEvents.count > developerEventLimit {
            developerEvents.removeLast(developerEvents.count - developerEventLimit)
        }
    }

    private func beginKeySwapDestinationCapture(source: KeyDescriptor) {
        let destinationPanel = KeyCapturePanelController(
            title: "Key Swapper",
            prompt: "Listening destination key...",
            detailText: source.displayName
        )
        destinationPanel.onCapture = { [weak self] destination in
            self?.addKeySwapRule(source: source, destination: destination)
        }
        destinationPanel.onClose = { [weak self, weak destinationPanel] in
            guard let destinationPanel, self?.keyCapturePanel === destinationPanel else {
                return
            }
            self?.keyCapturePanel = nil
        }
        keyCapturePanel = destinationPanel
        destinationPanel.show()
    }

    private func addKeySwapRule(source: KeyDescriptor, destination: KeyDescriptor) {
        keySwapRules.removeAll { $0.source.keyCode == source.keyCode }
        keySwapRules.append(KeySwapRule(source: source, destination: destination))
    }

    private func openLaunchTarget(_ assignment: LaunchTargetAssignment) {
        let url = URL(fileURLWithPath: assignment.path)

        switch assignment.kind {
        case .app:
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
        case .folder:
            NSWorkspace.shared.open(url)
        case .script:
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [assignment.path]
            try? process.run()
        }
    }

    private func saveAssignments() {
        let assignments = assignedActions.reduce(into: [String: MacroAssignment]()) { result, item in
            result[String(item.key)] = item.value
        }

        if let data = try? JSONEncoder().encode(assignments) {
            UserDefaults.standard.set(data, forKey: assignmentsDefaultsKey)
        }
    }

    private func saveKeySwapRules() {
        if let data = try? JSONEncoder().encode(keySwapRules) {
            UserDefaults.standard.set(data, forKey: keySwapRulesDefaultsKey)
        }
    }

    private static func loadAssignments() -> [UInt8: MacroAssignment] {
        guard let data = UserDefaults.standard.data(forKey: "MacroAssignments"),
              let rawAssignments = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        let decoder = JSONDecoder()
        return rawAssignments.reduce(into: [UInt8: MacroAssignment]()) { result, item in
            guard let code = UInt8(item.key),
                  JSONSerialization.isValidJSONObject(item.value),
                  let itemData = try? JSONSerialization.data(withJSONObject: item.value),
                  let assignment = try? decoder.decode(MacroAssignment.self, from: itemData)
            else {
                return
            }
            result[code] = assignment
        }
    }

    private static func loadKeySwapRules() -> [KeySwapRule] {
        guard let data = UserDefaults.standard.data(forKey: "KeySwapRules"),
              let rules = try? JSONDecoder().decode([KeySwapRule].self, from: data)
        else {
            return []
        }

        return rules
    }
}
