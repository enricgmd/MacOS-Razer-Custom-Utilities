import AppKit
import SwiftUI

public struct ContentView: View {
    @ObservedObject var model: MacroAppModel
    private let deviceStatusView: AnyView?
    private let footerCenterView: AnyView?

    public init(model: MacroAppModel, deviceStatusView: AnyView? = nil, footerCenterView: AnyView? = nil) {
        self.model = model
        self.deviceStatusView = deviceStatusView
        self.footerCenterView = footerCenterView
    }

    public var body: some View {
        ZStack {
            RazerBackdrop()

            VStack(alignment: .leading, spacing: 14) {
                header

                MacroKeyGrid(model: model)
                    .zIndex(2)

                keyboardSection
                    .zIndex(1)

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .frame(
            minWidth: 680,
            idealWidth: 680,
            maxWidth: 680,
            minHeight: 507,
            idealHeight: 507,
            maxHeight: 507
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            RazerLogoView()
                .frame(width: 46, height: 46)
                //.offset(y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Razer Custom Utilities")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
                    //.offset(y: 8)
                if let deviceStatusView {
                    deviceStatusView
                } else {
                    Text(model.deviceStatusLabel)
                        .font(.callout)
                        .foregroundColor(Color.white.opacity(0.62))
                        .lineLimit(1)
                        //.offset(y: 4)
                }
                if model.permissionState != .granted {
                    Text(model.permissionStatusLabel)
                        .font(.caption)
                        .foregroundColor(Color.razerGreen.opacity(0.86))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button("Macro keys enable/disable") {
                model.setMacroModeEnabled(!model.macroModeEnabled)
            }
            .buttonStyle(MacroKeysButtonStyle(isActive: model.macroModeEnabled))
            .disabled(!model.deviceConnected)
            .opacity(model.deviceConnected ? 1.0 : 0.42)
            .fixedSize()
            //.offset(y: 5)
        }
        .padding(.top, -2)
    }

    private var keyboardSection: some View {
        VStack(alignment: .trailing, spacing: 6) {
            keyboardReference
                .allowsHitTesting(model.developerModeEnabled)

            ZStack {
                HStack {
                    Button("Key swapper") {
                        NotificationCenter.default.post(name: .showKeySwapperWindow, object: nil)
                    }
                    .font(.callout.weight(.medium))
                    .buttonStyle(DarkUtilityButtonStyle())
                    .fixedSize()
                    .offset(y: 9)
                    .disabled(!model.deviceConnected)
                    .opacity(model.deviceConnected ? 1.0 : 0.42)

                    Spacer()

                    Toggle("Raw events viewer", isOn: Binding(
                        get: { model.developerModeEnabled },
                        set: { model.setDeveloperModeEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .font(.callout.weight(.medium))
                    .foregroundColor(Color.white.opacity(0.76))
                    .colorScheme(.dark)
                    .fixedSize()
                    .offset(y: 9)
                    .disabled(!model.deviceConnected)
                    .opacity(model.deviceConnected ? 1.0 : 0.42)
                }

                if let footerCenterView {
                    footerCenterView
                        .fixedSize()
                        .offset(y: 9)
                }
            }
            //.padding(.bottom, 2)
        }
    }

    private var keyboardReference: some View {
        ZStack {
            ResourceImage(name: "keyboard.png")
                .aspectRatio(contentMode: .fill)
                .frame(width: 632, height: 150)
                //.clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .offset(y: -10)
                .opacity(0.7)

            if model.developerModeEnabled {
                DeveloperTerminalView(model: model)
                    .frame(width: 600, height: 112)
                    .transition(.opacity)
            }
        }
        .frame(height: 130)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct DeveloperTerminalView: View {
    @ObservedObject var model: MacroAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("vendor-id=\(model.developerVendorID)  product-id=\(model.developerProductID)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Color.razerGreen)

            Divider()
                .background(Color.razerGreen.opacity(0.22))

            CopyableDeveloperEventTextView(events: model.developerEvents)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.razerGreen.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 12, x: 0, y: 5)
    }
}

private struct CopyableDeveloperEventTextView: NSViewRepresentable {
    let events: [String]

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CopyableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor.white.withAlphaComponent(0.90)
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = textView

        context.coordinator.textView = textView
        updateTextView(textView)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else {
            return
        }

        updateTextView(textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func updateTextView(_ textView: NSTextView) {
        let nextString = events.joined(separator: "\n")
        guard textView.string != nextString else {
            return
        }

        textView.string = nextString
    }

    final class Coordinator {
        weak var textView: NSTextView?
    }

    final class CopyableTextView: NSTextView {
        override var acceptsFirstResponder: Bool {
            true
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if shouldCopy(from: event) {
                copy(nil)
                return true
            }

            return super.performKeyEquivalent(with: event)
        }

        override func keyDown(with event: NSEvent) {
            if shouldCopy(from: event) {
                copy(nil)
                return
            }

            super.keyDown(with: event)
        }

        private func shouldCopy(from event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return flags.contains(.command) &&
                event.charactersIgnoringModifiers?.lowercased() == "c"
        }
    }
}

private struct DarkUtilityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(Color.white.opacity(0.86))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
    }
}

private struct MacroKeysButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundColor(isActive ? .black : Color.white.opacity(0.86))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.razerRed.opacity(0.9) : Color.white.opacity(configuration.isPressed ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isActive ? Color.razerRed.opacity(0.9) : Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: isActive ? Color.razerRed.opacity(0.80) : Color.clear, radius: isActive ? 10 : 0, x: 0, y: 0)
    }
}

private struct MacroKeyGrid: View {
    @ObservedObject var model: MacroAppModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ForEach(MacroKey.all.prefix(3)) { key in
                    MacroKeyButton(
                        model: model,
                        key: key,
                        isActive: model.activeKeyCodes.contains(key.id),
                        isEnabled: model.deviceConnected
                    )
                }
            }
            HStack(spacing: 14) {
                ForEach(MacroKey.all.suffix(3)) { key in
                    MacroKeyButton(
                        model: model,
                        key: key,
                        isActive: model.activeKeyCodes.contains(key.id),
                        isEnabled: model.deviceConnected
                    )
                }
            }
        }
    }
}

private struct MacroKeyButton: View {
    @ObservedObject var model: MacroAppModel
    let key: MacroKey
    let isActive: Bool
    let isEnabled: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 7) {
            Text(key.name)
                .font(.system(size: 33, weight: .black, design: .default))
                .foregroundColor(keyTitleColor)
            Text(model.assignedActionTitle(for: key))
                .font(.callout.weight(model.hasAssignment(for: key) ? .semibold : .medium))
                .foregroundColor(actionTitleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(borderColor, lineWidth: isHovered && isEnabled ? 2 : 1)
        )
        .overlay(keycapHighlight)
        .overlay(
            MacroAssignmentMenuOverlay(
                key: key,
                model: model,
                isEnabled: isEnabled,
                isHovered: $isHovered
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        )
        .foregroundColor(isHovered && isEnabled ? .white : Color.white.opacity(0.82))
        .scaleEffect(isHovered && isEnabled ? 1.025 : 1.0)
        .animation(.easeOut(duration: 0.08), value: isActive)
        .animation(.easeOut(duration: 0.08), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isEnabled)
    }

    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: backgroundColors),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.black.opacity(isEnabled ? 0.72 : 0.42), lineWidth: 4)
                .padding(4)
        }
        .shadow(color: isEnabled ? Color.black.opacity(0.64) : Color.black.opacity(0.24), radius: 8, x: 0, y: 5)
    }

    private var backgroundColors: [Color] {
        if !isEnabled {
            return [
                Color(red: 0.16, green: 0.17, blue: 0.17),
                Color(red: 0.08, green: 0.085, blue: 0.09)
            ]
        }

        if isHovered {
            return [
                            Color(red: 0.20, green: 0.30, blue: 0.21),
                            Color(red: 0.06, green: 0.11, blue: 0.07)
            ]
        }

        return [
                            Color(red: 0.15, green: 0.16, blue: 0.17),
                            Color(red: 0.045, green: 0.048, blue: 0.052)
        ]
    }

    private var keycapHighlight: some View {
        RoundedRectangle(cornerRadius: 7)
            .strokeBorder(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(isEnabled ? (isHovered ? 0.30 : 0.16) : 0.06),
                        Color.clear
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
            .padding(6)
    }

    private var keyTitleColor: Color {
        guard isEnabled else {
            return Color.white.opacity(0.26)
        }

        if isActive {
            return Color.macroActiveYellow
        }

        return isHovered ? .white : Color.white.opacity(0.82)
    }

    private var actionTitleColor: Color {
        guard isEnabled else {
            return Color.white.opacity(0.22)
        }

        if model.hasAssignment(for: key) {
            return isHovered ? Color.assignmentBlue.opacity(0.98) : Color.assignmentBlue
        }

        return isHovered ? Color.white.opacity(0.88) : Color.white.opacity(0.42)
    }

    private var borderColor: Color {
        guard isEnabled else {
            return Color.white.opacity(0.08)
        }

        return isHovered ? Color.razerGreen : Color.white.opacity(0.14)
    }
}

private struct MacroAssignmentMenuOverlay: NSViewRepresentable {
    let key: MacroKey
    let model: MacroAppModel
    let isEnabled: Bool
    @Binding var isHovered: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ClickMenuView {
        let view = ClickMenuView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.autoresizingMask = [.width, .height]
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ClickMenuView, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
    }

    final class Coordinator: NSObject {
        var parent: MacroAssignmentMenuOverlay

        init(parent: MacroAssignmentMenuOverlay) {
            self.parent = parent
        }

        func setHovered(_ hovered: Bool) {
            parent.isHovered = parent.isEnabled ? hovered : false
        }

        func showMenu(from view: NSView, event: NSEvent) {
            guard parent.isEnabled else {
                return
            }

            let menu = NSMenu()

            let shortcutItem = NSMenuItem(
                title: "Shortcut",
                action: #selector(beginShortcutCapture(_:)),
                keyEquivalent: ""
            )
            shortcutItem.target = self
            menu.addItem(shortcutItem)

            let openAppItem = NSMenuItem(
                title: "Open App/Script...",
                action: #selector(assignOpenApp(_:)),
                keyEquivalent: ""
            )
            openAppItem.target = self
            menu.addItem(openAppItem)

            let systemActionItem = NSMenuItem(title: "System Action", action: nil, keyEquivalent: "")
            let systemActionMenu = NSMenu()
            let openFolderItem = NSMenuItem(
                title: "Open Folder...",
                action: #selector(assignOpenFolder(_:)),
                keyEquivalent: ""
            )
            openFolderItem.target = self
            systemActionMenu.addItem(openFolderItem)

            for (index, action) in SystemActionKind.allCases.enumerated() {
                let item = NSMenuItem(
                    title: action.rawValue,
                    action: #selector(assignSystemAction(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                systemActionMenu.addItem(item)
            }
            systemActionItem.submenu = systemActionMenu
            menu.addItem(systemActionItem)

            let showThisAppItem = NSMenuItem(
                title: "Show/hide app",
                action: #selector(assignShowThisApp(_:)),
                keyEquivalent: ""
            )
            showThisAppItem.target = self
            menu.addItem(showThisAppItem)

            menu.addItem(.separator())

            let clearItem = NSMenuItem(
                title: "Clear Assignment",
                action: #selector(clearAssignment(_:)),
                keyEquivalent: ""
            )
            clearItem.target = self
            clearItem.isEnabled = parent.model.hasAssignment(for: parent.key)
            menu.addItem(clearItem)

            let point = view.convert(event.locationInWindow, from: nil)
            menu.popUp(positioning: nil, at: point, in: view)
        }

        @objc private func beginShortcutCapture(_ sender: NSMenuItem) {
            parent.model.beginShortcutCapture(for: parent.key)
        }

        @objc private func assignOpenApp(_ sender: NSMenuItem) {
            parent.model.beginOpenAppSelection(for: parent.key)
        }

        @objc private func assignOpenFolder(_ sender: NSMenuItem) {
            parent.model.beginOpenFolderSelection(for: parent.key)
        }

        @objc private func assignSystemAction(_ sender: NSMenuItem) {
            guard SystemActionKind.allCases.indices.contains(sender.tag) else {
                return
            }
            parent.model.assign(.systemAction(SystemActionKind.allCases[sender.tag]), to: parent.key)
        }

        @objc private func clearAssignment(_ sender: NSMenuItem) {
            parent.model.clearAssignment(for: parent.key)
        }

        @objc private func assignShowThisApp(_ sender: NSMenuItem) {
            parent.model.assign(.showThisApp, to: parent.key)
        }
    }

    final class ClickMenuView: NSView {
        weak var coordinator: Coordinator?
        private var trackingAreaRef: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingAreaRef {
                removeTrackingArea(trackingAreaRef)
            }

            let options: NSTrackingArea.Options = [
                .activeInActiveApp,
                .mouseEnteredAndExited,
                .inVisibleRect
            ]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingAreaRef = area
        }

        override func mouseEntered(with event: NSEvent) {
            coordinator?.setHovered(true)
        }

        override func mouseExited(with event: NSEvent) {
            coordinator?.setHovered(false)
        }

        override func mouseDown(with event: NSEvent) {
            coordinator?.showMenu(from: self, event: event)
        }

        override func rightMouseDown(with event: NSEvent) {
            coordinator?.showMenu(from: self, event: event)
        }
    }
}

private struct RazerBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.018, green: 0.020, blue: 0.023)
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.00, green: 0.16, blue: 0.08).opacity(0.72),
                    Color.clear,
                    Color(red: 0.18, green: 0.02, blue: 0.14).opacity(0.34)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .edgesIgnoringSafeArea(.all)
    }
}

private struct RazerLogoView: View {
    var body: some View {
        ResourceImage(name: "razer-ths-logo.png")
            .aspectRatio(contentMode: .fit)
            .shadow(color: Color.razerGreen.opacity(0.48), radius: 8, x: 0, y: 0)
    }
}

private struct ResourceImage: View {
    let name: String

    var body: some View {
        Group {
            if let image = AppAssets.image(named: name) {
                Image(nsImage: image)
                    .resizable()
            } else {
                Color.clear
            }
        }
    }
}

private extension Color {
    static let razerGreen = Color(red: 0.27, green: 0.84, blue: 0.17)
    static let razerRed = Color(red: 0.65, green: 0.10, blue: 0.25)
    static let macroActiveYellow = Color(red: 0.2, green: 1.0, blue: 0.10)
    static let assignmentBlue = Color(red: 0.20, green: 0.62, blue: 1.0)
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        let model = MacroAppModel()
        model.deviceConnected = true
        model.macroModeEnabled = true
        model.activeKeyCodes = [0x20, 0x24]

        return ContentView(model: model)
            .frame(width: 680, height: 500)
            .previewDisplayName("Razer Custom Utilities")
    }
}
#endif
