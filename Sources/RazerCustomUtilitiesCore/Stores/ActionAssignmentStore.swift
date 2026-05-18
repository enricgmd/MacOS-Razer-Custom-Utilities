import AppKit
import Foundation

public final class ActionAssignmentStore: ObservableObject {
    @Published private var assignedActions: [String: MacroAssignment]

    private let defaultsKey: String
    private let emptyTitle: String
    private var shortcutRecorder: ShortcutRecorderPanelController?

    public init(defaultsKey: String, emptyTitle: String = "Click to assign") {
        self.defaultsKey = defaultsKey
        self.emptyTitle = emptyTitle
        assignedActions = Self.loadAssignments(defaultsKey: defaultsKey)
    }

    public var systemActionTitles: [String] {
        SystemActionKind.allCases.map(\.rawValue)
    }

    public func assignedActionTitle(for id: String) -> String {
        assignedActions[id]?.displayTitle ?? emptyTitle
    }

    public func hasAssignment(for id: String) -> Bool {
        assignedActions[id] != nil
    }

    public func beginShortcutCapture(for id: String, title: String) {
        shortcutRecorder?.close()

        let recorder = ShortcutRecorderPanelController(keyName: title)
        recorder.onSave = { [weak self] shortcut in
            self?.assign(.shortcut(shortcut), to: id)
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

    public func beginOpenAppSelection(for id: String, title: String) {
        let panel = NSOpenPanel()
        panel.title = "Select App or Script"
        panel.prompt = "Assign"
        panel.message = "Choose the app or script to run with \(title)."
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

            self?.assign(.openApp(LaunchTargetAssignment(url: url)), to: id)
        }
    }

    public func beginOpenFolderSelection(for id: String, title: String) {
        let panel = NSOpenPanel()
        panel.title = "Select Folder"
        panel.prompt = "Assign"
        panel.message = "Choose the folder to open with \(title)."
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

            self?.assign(.openApp(LaunchTargetAssignment(folderURL: url)), to: id)
        }
    }

    public func assignSystemAction(at index: Int, to id: String) {
        guard SystemActionKind.allCases.indices.contains(index) else {
            return
        }

        assign(.systemAction(SystemActionKind.allCases[index]), to: id)
    }

    public func assignShowThisApp(to id: String) {
        assign(.showThisApp, to: id)
    }

    public func clearAssignment(for id: String) {
        assignedActions.removeValue(forKey: id)
        saveAssignments()
    }

    public func performAssignment(for id: String) {
        guard let assignment = assignedActions[id] else {
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

    public func shutdown() {
        shortcutRecorder?.close()
        shortcutRecorder = nil
    }

    private func assign(_ assignment: MacroAssignment, to id: String) {
        assignedActions[id] = assignment
        saveAssignments()
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
        if let data = try? JSONEncoder().encode(assignedActions) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    private static func loadAssignments(defaultsKey: String) -> [String: MacroAssignment] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let assignments = try? JSONDecoder().decode([String: MacroAssignment].self, from: data)
        else {
            return [:]
        }

        return assignments
    }
}
