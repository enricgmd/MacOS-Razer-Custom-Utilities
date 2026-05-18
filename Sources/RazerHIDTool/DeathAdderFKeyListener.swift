import AppKit
import ApplicationServices
import Foundation

enum DeathAdderFKeyListenerError: Error, CustomStringConvertible {
    case eventTapCreationFailed

    var description: String {
        switch self {
        case .eventTapCreationFailed:
            return "Unable to create DeathAdder F-key event tap. Check Input Monitoring / Accessibility permission for Terminal or Codex."
        }
    }
}

final class DeathAdderFKeyListener {
    private static let functionKeyNames: [Int: String] = [
        0xF710: "F13",
        0xF711: "F14",
        0xF712: "F15",
        0xF713: "F16",
        0xF714: "F17",
        0xF715: "F18",
        0xF716: "F19",
        0xF717: "F20",
        0xF718: "F21",
        0xF719: "F22",
        0xF71A: "F23",
        0xF71B: "F24"
    ]
    private static let virtualKeyNames: [Int64: String] = [
        0x69: "F13",
        0x6B: "F14",
        0x71: "F15",
        0x6A: "F16",
        0x40: "F17",
        0x4F: "F18",
        0x50: "F19",
        0x5A: "F20"
    ]
    private static let ansiFunctionKeyNames: [String: String] = [
        "\u{1B}[25~": "F13",
        "\u{1B}[26~": "F14",
        "\u{1B}[28~": "F15",
        "\u{1B}[29~": "F16",
        "\u{1B}[31~": "F17",
        "\u{1B}[32~": "F18",
        "\u{1B}[33~": "F19",
        "\u{1B}[34~": "F20"
    ]

    private let dateFormatter: DateFormatter
    private let debugUnmatchedEvents: Bool

    init(debugUnmatchedEvents: Bool = false) {
        self.debugUnmatchedEvents = debugUnmatchedEvents
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    func start() throws {
        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: deathAdderFKeyEventTapCallback,
            userInfo: context
        ) else {
            throw DeathAdderFKeyListenerError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        if debugUnmatchedEvents {
            print("Debugging F-key events at HID event tap. Press Ctrl-C to stop.")
        } else {
            print("Listening for DeathAdder buttons mapped to F13-F24. Press Ctrl-C to stop.")
        }
        CFRunLoopRun()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let keyName = functionKeyName(for: event) ?? Self.virtualKeyNames[keyCode] else {
            if debugUnmatchedEvents {
                printDebugLine(type: type, event: event, keyCode: keyCode)
            }
            return Unmanaged.passUnretained(event)
        }

        let timestamp = dateFormatter.string(from: Date())
        let label = eventLabel(for: type)
        let flags = format(flags: event.flags)

        print("[deathadder-\(label)] \(timestamp)  key=\(keyName)  keyCode=\(keyCode)  flags=\(flags)")
        return nil
    }

    private func printDebugLine(type: CGEventType, event: CGEvent, keyCode: Int64) {
        let timestamp = dateFormatter.string(from: Date())
        let label = eventLabel(for: type)
        let flags = format(flags: event.flags)
        let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat)
        let keyboardType = event.getIntegerValueField(.keyboardEventKeyboardType)
        let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? ""
        let escapedCharacters = characters
            .unicodeScalars
            .map { scalar -> String in
                if scalar.value == 0x1B {
                    return "ESC"
                }
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    return String(format: "U+%04X", scalar.value)
                }
                return String(scalar)
            }
            .joined(separator: " ")
        let scalars = characters
            .unicodeScalars
            .map { String(format: "U+%04X", $0.value) }
            .joined(separator: ",")
        let printableCharacters = escapedCharacters.isEmpty ? "-" : escapedCharacters
        let printableScalars = scalars.isEmpty ? "-" : scalars

        print("[fkey-debug-\(label)] \(timestamp)  keyCode=\(keyCode)  flags=\(flags)  repeat=\(autorepeat)  keyboardType=\(keyboardType)  chars=\(printableCharacters)  scalars=\(printableScalars)")
    }

    private func functionKeyName(for event: CGEvent) -> String? {
        guard let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers,
              let scalar = characters.unicodeScalars.first else {
            return nil
        }

        if let keyName = Self.ansiFunctionKeyNames[characters] {
            return keyName
        }

        return Self.functionKeyNames[Int(scalar.value)]
    }

    private func eventLabel(for type: CGEventType) -> String {
        switch type {
        case .keyDown:
            return "down"
        case .keyUp:
            return "up"
        default:
            return "event"
        }
    }

    private func format(flags: CGEventFlags) -> String {
        var parts: [String] = []

        if flags.contains(.maskCommand) { parts.append("cmd") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskAlternate) { parts.append("alt") }
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskSecondaryFn) { parts.append("fn") }
        if flags.contains(.maskAlphaShift) { parts.append("caps") }

        return parts.isEmpty ? "-" : parts.joined(separator: "+")
    }
}

private func deathAdderFKeyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let listener = Unmanaged<DeathAdderFKeyListener>.fromOpaque(userInfo).takeUnretainedValue()
    return listener.handle(type: type, event: event)
}
