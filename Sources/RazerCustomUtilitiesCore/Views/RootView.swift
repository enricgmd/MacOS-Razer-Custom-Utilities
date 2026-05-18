import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var keyboardModel: MacroAppModel
    @ObservedObject var deviceModel: DeviceSelectionModel
    @ObservedObject var deathAdderButtonModel: DeathAdderButtonModel
    @ObservedObject var deathAdderAssignmentStore: ActionAssignmentStore
    @ObservedObject var deathAdderRawEventModel: DeathAdderRawEventModel

    var body: some View {
        Group {
            if deviceModel.selectedDevice == .mouse {
                MousePlaceholderView(
                    deviceModel: deviceModel,
                    deathAdderButtonModel: deathAdderButtonModel,
                    deathAdderAssignmentStore: deathAdderAssignmentStore,
                    deathAdderRawEventModel: deathAdderRawEventModel
                )
            } else {
                ContentView(
                    model: keyboardModel,
                    deviceStatusView: AnyView(DeviceSelectorView(deviceModel: deviceModel)),
                    footerCenterView: AnyView(CapsLockLEDFixToggle(model: keyboardModel))
                )
            }
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
}

private struct MousePlaceholderView: View {
    @ObservedObject var deviceModel: DeviceSelectionModel
    @ObservedObject var deathAdderButtonModel: DeathAdderButtonModel
    @ObservedObject var deathAdderAssignmentStore: ActionAssignmentStore
    @ObservedObject var deathAdderRawEventModel: DeathAdderRawEventModel
    let showsHotspotPreview: Bool

    init(
        deviceModel: DeviceSelectionModel,
        deathAdderButtonModel: DeathAdderButtonModel,
        deathAdderAssignmentStore: ActionAssignmentStore,
        deathAdderRawEventModel: DeathAdderRawEventModel,
        showsHotspotPreview: Bool = false
    ) {
        self.deviceModel = deviceModel
        self.deathAdderButtonModel = deathAdderButtonModel
        self.deathAdderAssignmentStore = deathAdderAssignmentStore
        self.deathAdderRawEventModel = deathAdderRawEventModel
        self.showsHotspotPreview = showsHotspotPreview
    }

    var body: some View {
        ZStack {
            MouseRazerBackdrop()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 18) {
                    MouseRazerLogoView()
                        .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Razer Custom Utilities")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                        DeviceSelectorView(deviceModel: deviceModel)
                    }

                    Spacer()
                }
                .padding(.top, -2)

                Spacer(minLength: 0)

                ZStack {
                    MouseHeroImage(
                        deathAdderButtonModel: deathAdderButtonModel,
                        assignmentStore: deathAdderAssignmentStore,
                        isAssignmentEnabled: deviceModel.mouseConnected,
                        showsHotspotPreview: showsHotspotPreview,
                        disablesHotspotInteraction: deathAdderRawEventModel.isEnabled
                    )
                        .frame(width: 560, height: 320)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if deathAdderRawEventModel.isEnabled {
                        DeathAdderRawTerminalView(model: deathAdderRawEventModel)
                            .frame(width: 613, height: 320)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 0)

                HStack {
                    Toggle("Raw events viewer", isOn: Binding(
                        get: { deathAdderRawEventModel.isEnabled },
                        set: { deathAdderRawEventModel.setEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .font(.callout.weight(.medium))
                    .foregroundColor(Color.white.opacity(0.76))
                    .colorScheme(.dark)
                    .fixedSize()
                    .disabled(!deviceModel.mouseConnected)
                    .opacity(deviceModel.mouseConnected ? 1.0 : 0.42)

                    Spacer()
                }
                .offset(y: -1)
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
}

private struct MouseHeroImage: View {
    @ObservedObject var deathAdderButtonModel: DeathAdderButtonModel
    @ObservedObject var assignmentStore: ActionAssignmentStore
    let isAssignmentEnabled: Bool
    let showsHotspotPreview: Bool
    let disablesHotspotInteraction: Bool

    private let aspectRatio: CGFloat = 890.0 / 628.0
    private let hotspots: [MouseButtonHotspot] = [
        MouseButtonHotspot(id: "top-rear", label: "Top rear", centerX: 0.498, centerY: 0.192, width: 0.07, height: 0.06, rotation: -20),
        MouseButtonHotspot(id: "top-front", label: "Top front", centerX: 0.428, centerY: 0.258, width: 0.075, height: 0.060, rotation: -32),
        MouseButtonHotspot(id: "side-front", label: "Side front", centerX: 0.73, centerY: 0.492, width: 0.14, height: 0.070, rotation: -32),
        MouseButtonHotspot(id: "side-rear", label: "Side rear", centerX: 0.61, centerY: 0.628, width: 0.155, height: 0.048, rotation: -50)
    ]
    @State private var hoveredHotspotID: String?

    var body: some View {
        GeometryReader { geometry in
            let imageSize = fittedImageSize(in: geometry.size)
            let origin = CGPoint(
                x: (geometry.size.width - imageSize.width) / 2,
                y: (geometry.size.height - imageSize.height) / 2
            )

            ZStack {
                Group {
                    if let image = MouseAssets.image(named: "mouseHQ.png") {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Color.clear
                    }
                }

                ForEach(hotspots) { hotspot in
                    MouseHotspotView(
                        hotspot: hotspot,
                        isHovered: isHighlighted(hotspot)
                    )
                        .frame(
                            width: hotspot.width * imageSize.width,
                            height: hotspot.height * imageSize.height
                        )
                        .rotationEffect(.degrees(hotspot.rotation))
                        .position(
                            x: origin.x + hotspot.centerX * imageSize.width,
                            y: origin.y + hotspot.centerY * imageSize.height
                        )
                }

                ForEach(hotspots) { hotspot in
                    MouseCalloutLineView(
                        hotspot: hotspot,
                        imageSize: imageSize,
                        imageOrigin: origin,
                        containerSize: geometry.size,
                        isHovered: isHighlighted(hotspot)
                    )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }

                ForEach(hotspots) { hotspot in
                    MouseCalloutLabelView(
                        assignmentStore: assignmentStore,
                        hotspot: hotspot,
                        isHovered: isHighlighted(hotspot),
                        isEnabled: isAssignmentEnabled,
                        isInteractionDisabled: disablesHotspotInteraction,
                        hoveredHotspotID: $hoveredHotspotID
                    )
                    .position(hotspot.labelPoint(in: geometry.size))
                }
            }
        }
    }

    private func fittedImageSize(in container: CGSize) -> CGSize {
        let containerRatio = container.width / container.height
        if containerRatio > aspectRatio {
            let height = container.height
            return CGSize(width: height * aspectRatio, height: height)
        }

        let width = container.width
        return CGSize(width: width, height: width / aspectRatio)
    }

    private func isHighlighted(_ hotspot: MouseButtonHotspot) -> Bool {
        guard !disablesHotspotInteraction else {
            return false
        }

        return showsHotspotPreview ||
            hoveredHotspotID == hotspot.id ||
            deathAdderButtonModel.isActive(hotspot.id)
    }
}

private struct DeathAdderRawTerminalView: View {
    @ObservedObject var model: DeathAdderRawEventModel

    private var terminalGreen: Color {
        Color(red: 0.27, green: 0.84, blue: 0.17)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 13) {
                Text("vendor-id=0x1532  product-id=0x0084")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(terminalGreen)
                    .lineLimit(1)

                Spacer()

                Toggle("Filter movement", isOn: Binding(
                    get: { model.filtersMouseNoise },
                    set: { model.setFiltersMouseNoise($0) }
                ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.8))
                    .colorScheme(.dark)
                    .fixedSize()

                Toggle("Filter right/left click&scroll", isOn: Binding(
                    get: { model.filtersClickAndScrollNoise },
                    set: { model.setFiltersClickAndScrollNoise($0) }
                ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.8))
                    .colorScheme(.dark)
                    .fixedSize()
            }

            Divider()
                .background(terminalGreen.opacity(0.22))

            SelectableRawEventTextView(events: model.events)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.80))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(terminalGreen.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 12, x: 0, y: 5)
    }
}

private struct SelectableRawEventTextView: NSViewRepresentable {
    let events: [String]

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CopyableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
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

private struct MouseButtonHotspot: Identifiable {
    let id: String
    let label: String
    let centerX: CGFloat
    let centerY: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotation: Double

    var calloutX: CGFloat {
        switch id {
        case "top-rear":
            return 0.85
        case "top-front":
            return 0.15
        case "side-front":
            return 0.93
        case "side-rear":
            return 0.70
        default:
            return centerX
        }
    }

    var calloutY: CGFloat {
        switch id {
        case "top-rear":
            return -0.1
        case "top-front":
            return 0.1
        case "side-front":
            return 0.8
        case "side-rear":
            return 0.95
        default:
            return centerY
        }
    }

    var actionTitle: String {
        "Assign action"
    }

    func buttonPoint(imageSize: CGSize, imageOrigin: CGPoint) -> CGPoint {
        CGPoint(
            x: imageOrigin.x + centerX * imageSize.width,
            y: imageOrigin.y + centerY * imageSize.height
        )
    }

    func calloutPoint(in containerSize: CGSize) -> CGPoint {
        CGPoint(
            x: calloutX * containerSize.width,
            y: calloutY * containerSize.height
        )
    }

    func labelPoint(in containerSize: CGSize) -> CGPoint {
        let point = calloutPoint(in: containerSize)
        return CGPoint(
            x: point.x + labelOffsetX,
            y: point.y + labelOffsetY
        )
    }
}

private struct MouseCalloutLineView: View {
    let hotspot: MouseButtonHotspot
    let imageSize: CGSize
    let imageOrigin: CGPoint
    let containerSize: CGSize
    let isHovered: Bool

    private var accentColor: Color {
        Color(red: 0.6, green: 0.8, blue: 0.99)
    }

    var body: some View {
        let buttonPoint = hotspot.buttonPoint(imageSize: imageSize, imageOrigin: imageOrigin)
        let calloutPoint = hotspot.calloutPoint(in: containerSize)

        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: buttonPoint)
                path.addLine(to: calloutPoint)
            }
            .stroke(
                accentColor.opacity(0.9),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
            .allowsHitTesting(false)

            Circle()
                .fill(accentColor.opacity(isHovered ? 0.99 : 0.6))
                .frame(width: 5, height: 5)
                .position(calloutPoint)
                .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }
}

private struct MouseCalloutLabelView: View {
    @ObservedObject var assignmentStore: ActionAssignmentStore
    let hotspot: MouseButtonHotspot
    let isHovered: Bool
    let isEnabled: Bool
    let isInteractionDisabled: Bool
    @Binding var hoveredHotspotID: String?

    var body: some View {
        Text(assignmentStore.assignedActionTitle(for: hotspot.id))
            .font(.system(size: 12, weight: assignmentStore.hasAssignment(for: hotspot.id) ? .semibold : .medium))
            .foregroundColor(titleColor)
            .lineLimit(1)
            .minimumScaleFactor(0.76)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .cornerRadius(3)
            .fixedSize()
            .contentShape(Rectangle())
            .overlay(
                MouseAssignmentMenuOverlay(
                    hotspot: hotspot,
                    assignmentStore: assignmentStore,
                    isEnabled: isEnabled && !isInteractionDisabled,
                    hoveredHotspotID: $hoveredHotspotID
                )
            )
            .allowsHitTesting(!isInteractionDisabled)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isEnabled)
    }

    private var titleColor: Color {
        guard isEnabled else {
            return Color.white.opacity(0.28)
        }

        if assignmentStore.hasAssignment(for: hotspot.id) {
            return .white
        }

        return Color.white.opacity(isHovered ? 0.99 : 0.7)
    }

    private var backgroundColor: Color {
        guard isEnabled else {
            return Color.white.opacity(0.08)
        }

        return Color.blue.opacity(isHovered ? 0.8 : 0.4)
    }
}

private struct MouseAssignmentMenuOverlay: NSViewRepresentable {
    let hotspot: MouseButtonHotspot
    let assignmentStore: ActionAssignmentStore
    let isEnabled: Bool
    @Binding var hoveredHotspotID: String?

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
        var parent: MouseAssignmentMenuOverlay

        init(parent: MouseAssignmentMenuOverlay) {
            self.parent = parent
        }

        func setHovered(_ hovered: Bool) {
            if parent.isEnabled && hovered {
                parent.hoveredHotspotID = parent.hotspot.id
            } else if parent.hoveredHotspotID == parent.hotspot.id {
                parent.hoveredHotspotID = nil
            }
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

            for (index, title) in parent.assignmentStore.systemActionTitles.enumerated() {
                let item = NSMenuItem(
                    title: title,
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
            clearItem.isEnabled = parent.assignmentStore.hasAssignment(for: parent.hotspot.id)
            menu.addItem(clearItem)

            let point = view.convert(event.locationInWindow, from: nil)
            menu.popUp(positioning: nil, at: point, in: view)
        }

        @objc private func beginShortcutCapture(_ sender: NSMenuItem) {
            parent.assignmentStore.beginShortcutCapture(for: parent.hotspot.id, title: parent.hotspot.label)
        }

        @objc private func assignOpenApp(_ sender: NSMenuItem) {
            parent.assignmentStore.beginOpenAppSelection(for: parent.hotspot.id, title: parent.hotspot.label)
        }

        @objc private func assignOpenFolder(_ sender: NSMenuItem) {
            parent.assignmentStore.beginOpenFolderSelection(for: parent.hotspot.id, title: parent.hotspot.label)
        }

        @objc private func assignSystemAction(_ sender: NSMenuItem) {
            parent.assignmentStore.assignSystemAction(at: sender.tag, to: parent.hotspot.id)
        }

        @objc private func clearAssignment(_ sender: NSMenuItem) {
            parent.assignmentStore.clearAssignment(for: parent.hotspot.id)
        }

        @objc private func assignShowThisApp(_ sender: NSMenuItem) {
            parent.assignmentStore.assignShowThisApp(to: parent.hotspot.id)
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

private extension MouseButtonHotspot {
    var labelOffsetX: CGFloat {
        calloutX < 0.5 ? -5 : 0
    }

    var labelOffsetY: CGFloat {
        calloutY < 0.5 ? -15 : 15
    }
}

private struct MouseHotspotView: View {
    let hotspot: MouseButtonHotspot
    let isHovered: Bool

    var body: some View {
        Ellipse()
            .fill(Color(red: 0.2, green: 0.5, blue: 1).opacity(isHovered ? 1 : 0.3))
            .blur(radius: isHovered ? 5 : 3)
            .shadow(
                color: Color(red: 0.0, green: 0.5, blue: 0.99).opacity(isHovered ? 1 : 0.3),
                radius: isHovered ? 10 : 5,
            )
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.2), value: isHovered)
    }
}

private struct DeviceSelectorView: View {
    @ObservedObject var deviceModel: DeviceSelectionModel

    var body: some View {
        Group {
            if deviceModel.availableDevices.isEmpty {
                Text(deviceModel.statusTitle)
                    .font(.callout)
                    .foregroundColor(Color.white.opacity(0.8))
                    .lineLimit(1)
                    .frame(width: 220, alignment: .leading)
            } else {
                Picker("", selection: $deviceModel.selectedDevice) {
                    ForEach(deviceModel.availableDevices) { device in
                        Text(device.title).tag(device)
                    }
                }
                .labelsHidden()
                .pickerStyle(PopUpButtonPickerStyle())
                .frame(width: 190, alignment: .leading)
                .colorScheme(.dark)
            }
        }
    }
}

private struct CapsLockLEDFixToggle: View {
    @ObservedObject var model: MacroAppModel

    var body: some View {
        Toggle("Fix CapsLock LED", isOn: Binding(
            get: { model.capsLockLEDFixEnabled },
            set: { model.setCapsLockLEDFixEnabled($0) }
        ))
        .toggleStyle(.checkbox)
        .font(.callout.weight(.medium))
        .foregroundColor(Color.white.opacity(0.76))
        .colorScheme(.dark)
        .disabled(!model.deviceConnected)
        .opacity(model.deviceConnected ? 1.0 : 0.42)
    }
}

private struct MouseRazerBackdrop: View {
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

private struct MouseRazerLogoView: View {
    var body: some View {
        Group {
            if let image = MouseAssets.image(named: "razer-ths-logo.png") {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .shadow(color: Color(red: 0.27, green: 0.84, blue: 0.17).opacity(0.48), radius: 8, x: 0, y: 0)
    }
}

private enum MouseAssets {
    static func image(named name: String) -> NSImage? {
        let candidateURLs = [
            Bundle.module.resourceURL?.appendingPathComponent("graphics").appendingPathComponent(name),
            Bundle.main.resourceURL?.appendingPathComponent("graphics").appendingPathComponent(name),
            sourceGraphicsURL.appendingPathComponent(name)
        ].compactMap { $0 }

        for url in candidateURLs {
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return AppAssets.image(named: name)
    }

    private static var sourceGraphicsURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("graphics")
    }
}

#if DEBUG
private extension DeviceSelectionModel {
    static func preview(selectedDevice: RazerDeviceSelection = .mouse) -> DeviceSelectionModel {
        let model = DeviceSelectionModel()
        model.keyboardConnected = true
        model.mouseConnected = true
        model.selectedDevice = selectedDevice
        return model
    }
}

struct RootView_Previews: PreviewProvider {
    private static let keyboardModel = MacroAppModel()
    private static let deathAdderAssignmentStore = ActionAssignmentStore(defaultsKey: "DeathAdderAssignmentsPreview", emptyTitle: "Assign action")
    private static let deathAdderButtonModel = DeathAdderButtonModel()
    private static let deathAdderRawEventModel = DeathAdderRawEventModel()
    private static let mouseDeviceModel = DeviceSelectionModel.preview(selectedDevice: .mouse)
    private static let keyboardDeviceModel = DeviceSelectionModel.preview(selectedDevice: .keyboard)

    static var previews: some View {
        Group {
            MousePlaceholderView(
                deviceModel: mouseDeviceModel,
                deathAdderButtonModel: deathAdderButtonModel,
                deathAdderAssignmentStore: deathAdderAssignmentStore,
                deathAdderRawEventModel: deathAdderRawEventModel,
                showsHotspotPreview: false
            )
                .previewDisplayName("DeathAdder V2")

            RootView(
                keyboardModel: keyboardModel,
                deviceModel: keyboardDeviceModel,
                deathAdderButtonModel: deathAdderButtonModel,
                deathAdderAssignmentStore: deathAdderAssignmentStore,
                deathAdderRawEventModel: deathAdderRawEventModel
            )
                .previewDisplayName("BlackWidow V4 X")
        }
    }
}
#endif
