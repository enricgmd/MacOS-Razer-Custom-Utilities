import AppKit
import SwiftUI

final class KeyCapturePanelController: NSObject, NSWindowDelegate, ObservableObject {
    @Published var displayText: String

    var onCapture: ((KeyDescriptor) -> Void)?
    var onClose: (() -> Void)?

    private let title: String
    private let prompt: String
    let detailText: String?
    private var panel: NSPanel?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    init(title: String, prompt: String, detailText: String? = nil) {
        self.title = title
        self.prompt = prompt
        self.detailText = detailText
        displayText = prompt
    }

    func show() {
        if panel == nil {
            let hostingView = NSHostingView(rootView: KeyCaptureView(controller: self))
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 390, height: detailText == nil ? 150 : 184),
                styleMask: [.titled, .closable, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.title = ""
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

    func windowWillClose(_ notification: Notification) {
        removeEventCapture()
        onClose?()
    }

    private func installEventCapture() {
        removeEventCapture()

        let events = (1 << CGEventType.keyDown.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(events),
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return nil
                }

                let controller = Unmanaged<KeyCapturePanelController>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = controller.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return nil
                }

                if let descriptor = KeyDescriptor(event: event, type: type) {
                    DispatchQueue.main.async {
                        controller.displayText = descriptor.displayName
                        controller.onCapture?(descriptor)
                        controller.close()
                    }
                }

                return nil
            },
            userInfo: pointer
        )

        guard let eventTap else {
            displayText = "Unable to listen for keys"
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func removeEventCapture() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }

        eventTapSource = nil
        eventTap = nil
    }
}

private struct KeyCaptureView: View {
    @ObservedObject var controller: KeyCapturePanelController

    var body: some View {
        VStack(spacing: 16) {
            if let detailText = controller.detailText {
                Text(detailText)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Text(controller.displayText)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 42)
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
            }
        }
        .padding(18)
        .frame(width: 390, height: controller.detailText == nil ? 150 : 184)
    }
}
