import AppKit

struct KeyDescriptor: Codable, Equatable, Hashable {
    let keyCode: UInt16
    let displayName: String
    let modifierRawValue: UInt

    var isModifier: Bool {
        Self.modifierFlags[keyCode] != nil
    }

    var modifierFlag: CGEventFlags? {
        Self.modifierFlags[keyCode]
    }

    var cgEventFlags: CGEventFlags {
        let modifiers = NSEvent.ModifierFlags(rawValue: modifierRawValue)
        var flags = CGEventFlags()

        if modifiers.contains(.option) {
            flags.insert(.maskAlternate)
        }
        if modifiers.contains(.shift) {
            flags.insert(.maskShift)
        }

        return flags
    }

    init(keyCode: UInt16, displayName: String? = nil, modifiers: NSEvent.ModifierFlags = []) {
        self.keyCode = keyCode
        self.modifierRawValue = modifiers.intersection([.option, .shift]).rawValue
        self.displayName = displayName ?? Self.displayName(for: keyCode)
    }

    init?(event: CGEvent, type: CGEventType) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard Self.isAllowedForKeySwapper(keyCode) else {
            return nil
        }

        switch type {
        case .keyDown:
            break
        default:
            return nil
        }

        guard let nsEvent = NSEvent(cgEvent: event),
              !nsEvent.modifierFlags.contains(.command),
              !nsEvent.modifierFlags.contains(.control),
              Self.hasPrintableCharacter(nsEvent)
        else {
            return nil
        }

        let modifiers = nsEvent.modifierFlags.intersection([.option, .shift])
        self.init(
            keyCode: keyCode,
            displayName: Self.displayName(for: keyCode, event: event),
            modifiers: modifiers
        )
    }

    static func displayName(for keyCode: UInt16, event: CGEvent? = nil) -> String {
        if let event,
           let eventName = eventDisplayName(event) {
            return eventName
        }

        if let namedKey = namedKeys[keyCode] {
            return namedKey
        }

        return "Key \(keyCode)"
    }

    private static func hasPrintableCharacter(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49 || eventDisplayName(event) != nil else {
            return false
        }

        return true
    }

    private static func eventDisplayName(_ event: CGEvent?) -> String? {
        guard let event,
              let nsEvent = NSEvent(cgEvent: event)
        else {
            return nil
        }

        if nsEvent.keyCode == 49 {
            return "Space"
        }

        if let chars = nsEvent.characters, isPrintable(chars) {
            return chars.uppercased()
        }

        if let chars = nsEvent.charactersIgnoringModifiers, isPrintable(chars) {
            return chars.uppercased()
        }

        return nil
    }

    private static func eventDisplayName(_ event: NSEvent) -> String? {
        if event.keyCode == 49 {
            return "Space"
        }

        if let chars = event.characters, isPrintable(chars) {
            return chars.uppercased()
        }

        if let chars = event.charactersIgnoringModifiers, isPrintable(chars) {
            return chars.uppercased()
        }

        return nil
    }

    private static func isPrintable(_ chars: String) -> Bool {
        guard chars.count == 1,
              let scalar = chars.unicodeScalars.first
        else {
            return false
        }

        return !CharacterSet.controlCharacters.contains(scalar)
            && !CharacterSet.newlines.contains(scalar)
    }

    static let ignoredKeyCodes = Set<UInt16>([
        57 // Caps Lock
    ])

    static func isAllowedForKeySwapper(_ keyCode: UInt16) -> Bool {
        allowedKeySwapKeyCodes.contains(keyCode)
    }

    static let modifierFlags: [UInt16: CGEventFlags] = [
        54: .maskCommand,
        55: .maskCommand,
        56: .maskShift,
        60: .maskShift,
        58: .maskAlternate,
        61: .maskAlternate,
        59: .maskControl,
        62: .maskControl
    ]

    private static let namedKeys: [UInt16: String] = [
        0: "A",
        1: "S",
        2: "D",
        3: "F",
        4: "H",
        5: "G",
        6: "Z",
        7: "X",
        8: "C",
        9: "V",
        10: "§",
        11: "B",
        12: "Q",
        13: "W",
        14: "E",
        15: "R",
        16: "Y",
        17: "T",
        18: "1",
        19: "2",
        20: "3",
        21: "4",
        22: "6",
        23: "5",
        24: "=",
        25: "9",
        26: "7",
        27: "-",
        28: "8",
        29: "0",
        30: "]",
        31: "O",
        32: "U",
        33: "`",
        34: "I",
        35: "P",
        36: "Return",
        37: "L",
        38: "J",
        39: "´",
        40: "K",
        41: ";",
        42: "\\",
        43: ",",
        44: "/",
        45: "N",
        46: "M",
        47: ".",
        48: "Tab",
        49: "Space",
        50: "º",
        51: "Delete",
        53: "Esc",
        54: "Right Cmd",
        55: "Cmd",
        56: "Shift",
        58: "Opt",
        59: "Ctrl",
        60: "Right Shift",
        61: "Right Opt",
        62: "Right Ctrl",
        64: "F17",
        65: "Keypad .",
        67: "Keypad *",
        69: "Keypad +",
        71: "Num Lock",
        75: "Keypad /",
        76: "Keypad Enter",
        78: "Keypad -",
        79: "F18",
        80: "F19",
        81: "Keypad =",
        82: "Keypad 0",
        83: "Keypad 1",
        84: "Keypad 2",
        85: "Keypad 3",
        86: "Keypad 4",
        87: "Keypad 5",
        88: "Keypad 6",
        89: "Keypad 7",
        90: "F20",
        91: "Keypad 8",
        92: "Keypad 9",
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
        114: "Insert",
        115: "Home",
        116: "Page Up",
        117: "Forward Delete",
        118: "F4",
        119: "End",
        120: "F2",
        121: "Page Down",
        122: "F1",
        123: "Left",
        124: "Right",
        125: "Down",
        126: "Up"
    ]

    private static let allowedKeySwapKeyCodes = Set<UInt16>([
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17,
        18, 19, 20, 21, 22, 23, 24, 25,
        26, 27, 28, 29, 30, 31, 32, 33,
        34, 35, 37, 38, 39, 40, 41, 42,
        43, 44, 45, 46, 47, 49, 50,
        65, 67, 69, 75, 78, 81, 82, 83,
        84, 85, 86, 87, 88, 89, 91, 92
    ])
}

extension KeyDescriptor {
    private enum CodingKeys: String, CodingKey {
        case keyCode
        case displayName
        case modifierRawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        displayName = try container.decode(String.self, forKey: .displayName)
        modifierRawValue = try container.decodeIfPresent(UInt.self, forKey: .modifierRawValue) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(modifierRawValue, forKey: .modifierRawValue)
    }
}

struct KeySwapRule: Identifiable, Codable, Equatable {
    let id: UUID
    let source: KeyDescriptor
    let destination: KeyDescriptor

    init(id: UUID = UUID(), source: KeyDescriptor, destination: KeyDescriptor) {
        self.id = id
        self.source = source
        self.destination = destination
    }

    var displayTitle: String {
        "\(source.displayName) -> \(destination.displayName)"
    }
}
