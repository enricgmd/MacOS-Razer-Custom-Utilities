import AppKit
import ApplicationServices
import Foundation

enum KeyboardEventMonitorError: Error, CustomStringConvertible {
    case eventTapCreationFailed

    var description: String {
        switch self {
        case .eventTapCreationFailed:
            return "Unable to create keyboard event tap. Check that the host app has Input Monitoring / Accessibility permission."
        }
    }
}

final class KeyboardEventMonitor {
    private let dateFormatter: DateFormatter

    init() {
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    func start() throws {
        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: keyboardEventTapCallback,
            userInfo: context
        ) else {
            throw KeyboardEventMonitorError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("Listening for keyboard events. Press Ctrl-C to stop.")
        CFRunLoopRun()
    }

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        let timestamp = dateFormatter.string(from: Date())
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let label = eventLabel(for: type)

        var components = [
            "[\(label)]",
            timestamp,
            "keyCode=\(keyCode)",
            "flags=\(format(flags: flags))"
        ]

        if let characters = characters(for: type, event: event), !characters.isEmpty {
            components.append("chars=\"\(characters)\"")
        }

        print(components.joined(separator: "  "))
        return Unmanaged.passUnretained(event)
    }

    private func characters(for type: CGEventType, event: CGEvent) -> String? {
        guard type == .keyDown || type == .keyUp else {
            return nil
        }

        guard let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers else {
            return nil
        }

        return characters
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func eventLabel(for type: CGEventType) -> String {
        switch type {
        case .keyDown:
            return "down"
        case .keyUp:
            return "up"
        case .flagsChanged:
            return "flags"
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

        if parts.isEmpty {
            return "-"
        }

        return parts.joined(separator: "+")
    }
}

private func keyboardEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let monitor = Unmanaged<KeyboardEventMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    return monitor.handle(proxy: proxy, type: type, event: event)
}
