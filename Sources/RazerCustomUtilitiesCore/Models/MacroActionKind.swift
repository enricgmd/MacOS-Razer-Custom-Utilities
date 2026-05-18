import AppKit

struct ShortcutAssignment: Codable, Equatable {
    let keyCode: UInt16
    let modifierRawValue: UInt
    let keyName: String

    var displayTitle: String {
        let modifiers = NSEvent.ModifierFlags(rawValue: modifierRawValue)
        var parts: [String] = []

        if modifiers.contains(.command) {
            parts.append("Cmd")
        }
        if modifiers.contains(.control) {
            parts.append("Ctrl")
        }
        if modifiers.contains(.option) {
            parts.append("Opt")
        }
        if modifiers.contains(.shift) {
            parts.append("Shift")
        }

        parts.append(keyName)
        return parts.joined(separator: "+")
    }

    var cgEventFlags: CGEventFlags {
        let modifiers = NSEvent.ModifierFlags(rawValue: modifierRawValue)
        var flags = CGEventFlags()

        if modifiers.contains(.command) {
            flags.insert(.maskCommand)
        }
        if modifiers.contains(.control) {
            flags.insert(.maskControl)
        }
        if modifiers.contains(.option) {
            flags.insert(.maskAlternate)
        }
        if modifiers.contains(.shift) {
            flags.insert(.maskShift)
        }

        return flags
    }

    init?(event: NSEvent) {
        guard !Self.modifierKeyCodes.contains(event.keyCode),
              !Self.ignoredKeyCodes.contains(event.keyCode)
        else {
            return nil
        }

        keyCode = event.keyCode
        modifierRawValue = event.modifierFlags
            .intersection([.command, .control, .option, .shift])
            .rawValue
        keyName = Self.keyName(for: event)
    }

    private static let modifierKeyCodes = Set<UInt16>([54, 55, 56, 57, 58, 59, 60, 61, 62])
    private static let ignoredKeyCodes = Set<UInt16>([
        53,  // Esc
        71,  // Num Lock / Clear
        76,  // Keypad Enter
        105, // Print Screen / F13
        107, // Scroll Lock / F14
        113, // Pause / F15
        114, // Insert
        115, // Home
        116, // Page Up
        117, // Forward Delete
        119, // End
        121  // Page Down
    ])

    private static func keyName(for event: NSEvent) -> String {
        if let namedKey = namedKeys[event.keyCode] {
            return namedKey
        }

        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            return characters.uppercased()
        }

        return "Key \(event.keyCode)"
    }

    private static let namedKeys: [UInt16: String] = [
        33: "`",
        36: "Return",
        39: "´",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Esc",
        64: "F17",
        79: "F18",
        80: "F19",
        90: "F20",
        96: "F5",
        97: "F6",
        98: "F7",
        99: "F3",
        100: "F8",
        101: "F9",
        103: "F11",
        105: "F13",
        106: "F16",
        107: "F14",
        109: "F10",
        111: "F12",
        113: "F15",
        118: "F4",
        120: "F2",
        122: "F1",
        123: "Left",
        124: "Right",
        125: "Down",
        126: "Up"
    ]
}

enum SystemActionKind: String, CaseIterable, Codable {
    case createFolder = "Create Folder"
    case launchPad = "Launch Pad"
    case search = "Search"
    case forceQuit = "Force Quit"
    case sleep = "Sleep"
    case shutdown = "Shutdown"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported system action: \(rawValue)"
            )
        }

        self = value
    }
}

enum LaunchTargetKind: String, Codable {
    case app
    case folder
    case script
}

struct LaunchTargetAssignment: Codable, Equatable {
    let path: String
    let displayName: String
    let kind: LaunchTargetKind

    init(url: URL) {
        path = url.path
        if url.pathExtension.lowercased() == "app" {
            kind = .app
        } else if url.hasDirectoryPath {
            kind = .folder
        } else {
            kind = .script
        }
        switch kind {
        case .app:
            displayName = url.deletingPathExtension().lastPathComponent
        case .folder:
            displayName = url.lastPathComponent
        case .script:
            displayName = url.lastPathComponent
        }
    }

    init(path: String, displayName: String) {
        self.path = path
        self.displayName = displayName
        kind = URL(fileURLWithPath: path).pathExtension.lowercased() == "app" ? .app : .script
    }

    init(folderURL: URL) {
        path = folderURL.path
        displayName = folderURL.lastPathComponent
        kind = .folder
    }

    var displayTitle: String {
        switch kind {
        case .app:
            return "App: \(displayName)"
        case .folder:
            return "Folder: \(displayName)"
        case .script:
            return "Script: \(displayName)"
        }
    }
}

enum MacroAssignment: Equatable {
    case shortcut(ShortcutAssignment)
    case openApp(LaunchTargetAssignment?)
    case systemAction(SystemActionKind)
    case showThisApp

    var displayTitle: String {
        switch self {
        case .shortcut(let shortcut):
            return shortcut.displayTitle
        case .openApp(let assignment):
            return assignment?.displayTitle ?? "Open App/Script..."
        case .systemAction(let action):
            return action.rawValue
        case .showThisApp:
            return "Show/hide app"
        }
    }
}

extension MacroAssignment: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case shortcut
        case openApp
        case systemAction
        case showThisApp
    }

    private enum AssignmentType: String, Codable {
        case shortcut
        case openApp
        case systemAction
        case showThisApp
    }

    init(from decoder: Decoder) throws {
        if let legacy = try? LegacyAssignment(from: decoder) {
            self = legacy.assignment
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(AssignmentType.self, forKey: .type)

        switch type {
        case .shortcut:
            self = .shortcut(try container.decode(ShortcutAssignment.self, forKey: .shortcut))
        case .openApp:
            self = .openApp(try container.decodeIfPresent(LaunchTargetAssignment.self, forKey: .openApp))
        case .systemAction:
            self = .systemAction(try container.decode(SystemActionKind.self, forKey: .systemAction))
        case .showThisApp:
            self = .showThisApp
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .shortcut(let shortcut):
            try container.encode(AssignmentType.shortcut, forKey: .type)
            try container.encode(shortcut, forKey: .shortcut)
        case .openApp(let assignment):
            try container.encode(AssignmentType.openApp, forKey: .type)
            try container.encodeIfPresent(assignment, forKey: .openApp)
        case .systemAction(let action):
            try container.encode(AssignmentType.systemAction, forKey: .type)
            try container.encode(action, forKey: .systemAction)
        case .showThisApp:
            try container.encode(AssignmentType.showThisApp, forKey: .type)
        }
    }

    private struct LegacyAssignment: Decodable {
        let assignment: MacroAssignment

        private enum CodingKeys: String, CodingKey {
            case shortcut
            case openApp
            case systemAction
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if container.contains(.openApp) {
                if let launchTarget = try? container.decode(LaunchTargetAssignment.self, forKey: .openApp) {
                    assignment = .openApp(launchTarget)
                } else if let legacy = try? container.decode(LegacyOpenAppAssignment.self, forKey: .openApp) {
                    assignment = .openApp(LaunchTargetAssignment(path: legacy.path, displayName: legacy.displayName))
                } else {
                    assignment = .openApp(nil)
                }
            } else if container.contains(.shortcut) {
                assignment = .shortcut(try container.decode(ShortcutAssignment.self, forKey: .shortcut))
            } else if container.contains(.systemAction) {
                guard let action = try? container.decode(SystemActionKind.self, forKey: .systemAction) else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported legacy system action.")
                    )
                }
                assignment = .systemAction(action)
            } else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown macro assignment.")
                )
            }
        }

        private struct LegacyOpenAppAssignment: Decodable {
            let path: String
            let displayName: String
        }
    }
}
