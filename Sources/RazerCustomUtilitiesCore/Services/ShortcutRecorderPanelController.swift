import AppKit
import SwiftUI

final class ShortcutRecorderPanelController: NSObject, NSWindowDelegate, ObservableObject {
    @Published var capturedShortcut: ShortcutAssignment?
    @Published var displayText = "Listening..."

    var onSave: ((ShortcutAssignment) -> Void)?
    var onClose: (() -> Void)?

    let keyName: String
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var readyForNewCapture = true

    init(keyName: String) {
        self.keyName = keyName
    }

    func show() {
        if panel == nil {
            let view = ShortcutRecorderView(controller: self)
            let hostingView = NSHostingView(rootView: view)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 184),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = "Shortcut assign"
            panel.contentView = hostingView
            panel.delegate = self
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.center()
            self.panel = panel
        }

        installEventCapture()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.close()
    }

    func save() {
        guard let capturedShortcut else {
            return
        }

        onSave?(capturedShortcut)
        close()
    }

    func windowWillClose(_ notification: Notification) {
        removeEventCapture()
        onClose?()
    }

    private func installEventCapture() {
        removeEventCapture()

        let events = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(events),
            callback: { proxy, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let controller = Unmanaged<ShortcutRecorderPanelController>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = controller.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return nil
                }

                DispatchQueue.main.async {
                    controller.handle(cgEvent: event, type: type)
                }

                return nil
            },
            userInfo: pointer
        )

        if let eventTap {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            eventTapSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return
        }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    private func removeEventCapture() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        eventTapSource = nil
        eventTap = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            guard let shortcut = ShortcutAssignment(event: event) else {
                return
            }
            capturedShortcut = shortcut
            displayText = shortcut.displayTitle
            readyForNewCapture = false
        case .keyUp:
            if capturedShortcut != nil {
                let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                readyForNewCapture = modifiers.isEmpty
            }
        case .flagsChanged:
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            updateLiveModifierDisplay(modifiers)
        default:
            break
        }
    }

    private func handle(cgEvent: CGEvent, type: CGEventType) {
        switch type {
        case .keyDown:
            if let event = NSEvent(cgEvent: cgEvent),
               let shortcut = ShortcutAssignment(event: event) {
                capturedShortcut = shortcut
                displayText = shortcut.displayTitle
                readyForNewCapture = false
            }
        case .keyUp:
            if capturedShortcut != nil {
                let modifiers = modifierFlags(from: cgEvent.flags)
                readyForNewCapture = modifiers.isEmpty
            }
        case .flagsChanged:
            let modifiers = modifierFlags(from: cgEvent.flags)
            updateLiveModifierDisplay(modifiers)
        default:
            break
        }
    }

    private func updateLiveModifierDisplay(_ modifiers: NSEvent.ModifierFlags) {
        if capturedShortcut != nil && !readyForNewCapture {
            if modifiers.isEmpty {
                readyForNewCapture = true
            }
            return
        }

        if modifiers.isEmpty {
            if capturedShortcut == nil {
                displayText = "Listening..."
            }
        } else {
            capturedShortcut = nil
            displayText = modifierDisplayTitle(for: modifiers)
        }
    }

    private func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var modifiers = NSEvent.ModifierFlags()

        if flags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        if flags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        if flags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.maskShift) {
            modifiers.insert(.shift)
        }

        return modifiers
    }

    private func modifierDisplayTitle(for modifiers: NSEvent.ModifierFlags) -> String {
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

        return parts.isEmpty ? "Listening..." : parts.joined(separator: "+")
    }
}

private struct ShortcutRecorderView: View {
    @ObservedObject var controller: ShortcutRecorderPanelController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(controller.keyName)
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)

            Text(controller.displayText)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel") {
                    controller.close()
                }
                Button("Save") {
                    controller.save()
                }
                .disabled(controller.capturedShortcut == nil)
            }
        }
        .padding(18)
        .frame(width: 320, height: 184)
    }
}
