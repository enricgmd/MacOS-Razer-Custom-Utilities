import AppKit

enum ShortcutDispatcher {
    static func post(_ shortcut: ShortcutAssignment) {
        post(keyCode: shortcut.keyCode, flags: shortcut.cgEventFlags)
    }

    static func post(keyCode: UInt16, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(keyCode)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)
    }
}
