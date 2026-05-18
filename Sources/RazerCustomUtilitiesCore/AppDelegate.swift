import AppKit
import ServiceManagement
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let keyboardModel = MacroAppModel()
    private let deviceModel = DeviceSelectionModel()
    private let deathAdderAssignmentStore = ActionAssignmentStore(
        defaultsKey: "DeathAdderAssignments",
        emptyTitle: "Assign action"
    )
    private let deathAdderFKeySuppressor = DeathAdderFKeySuppressor()
    private let deathAdderTopButtonConfigurator = DeathAdderTopButtonConfigurator()
    private lazy var deathAdderButtonModel = DeathAdderButtonModel(
        assignmentStore: deathAdderAssignmentStore,
        fKeySuppressor: deathAdderFKeySuppressor
    )
    private let deathAdderRawEventModel = DeathAdderRawEventModel()

    private var window: NSWindow?
    private var keySwapperWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var launchMinimizedItem: NSMenuItem?

    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    private let showWindowAtLaunchDefaultsKey = "ShowWindowAtLaunch"

    private var shouldShowWindowAtLaunch: Bool {
        get {
            guard UserDefaults.standard.object(forKey: showWindowAtLaunchDefaultsKey) != nil else {
                return true
            }

            return UserDefaults.standard.bool(forKey: showWindowAtLaunchDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showWindowAtLaunchDefaultsKey)
            updateLaunchMinimizedMenuItem()
        }
    }

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showWindowFromNotification),
            name: .showRazerCustomUtilitiesWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleWindowFromNotification),
            name: .toggleRazerCustomUtilitiesWindow,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showKeySwapperWindowFromNotification),
            name: .showKeySwapperWindow,
            object: nil
        )

        configureMainMenu()
        configureWindow()
        configureKeySwapperWindow()
        configureStatusItem()

        keyboardModel.start()
        deviceModel.onMouseConnected = { [weak self] in
            self?.deathAdderTopButtonConfigurator.ensureDefaultAssignmentsInBackground(reason: "mouse-connected")
        }
        deviceModel.start(keyboardModel: keyboardModel)
        deathAdderFKeySuppressor.start()
        deathAdderButtonModel.start()

        if shouldShowWindowAtLaunch {
            showWindow()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        deathAdderRawEventModel.stop()
        deathAdderButtonModel.stop()
        deathAdderAssignmentStore.shutdown()
        deathAdderFKeySuppressor.stop()
        deviceModel.shutdown()
        keyboardModel.shutdown()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        updateActivationPolicy()
        return false
    }

    public func menuWillOpen(_ menu: NSMenu) {
        updateLaunchAtLoginMenuItem()
        updateLaunchMinimizedMenuItem()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(
            NSMenuItem(
                title: "Quit Razer Custom Utilities",
                action: #selector(quit),
                keyEquivalent: "q"
            )
        )

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func configureWindow() {
        let rootView = RootView(
            keyboardModel: keyboardModel,
            deviceModel: deviceModel,
            deathAdderButtonModel: deathAdderButtonModel,
            deathAdderAssignmentStore: deathAdderAssignmentStore,
            deathAdderRawEventModel: deathAdderRawEventModel
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "Razer Custom Utilities \(appVersion)"
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.standardWindowButton(.zoomButton)?.isHidden = true
        self.window = window
    }

    private func configureKeySwapperWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.center()
        window.title = "Key Swapper"
        window.contentView = NSHostingView(rootView: KeySwapperView(model: keyboardModel))
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.keySwapperWindow = window
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = AppAssets.image(named: "razer-ths-logo.png") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = false
                button.image = image
            } else {
                button.title = "R"
            }
        }

        let menu = NSMenu()
        menu.delegate = self

        let showItem = NSMenuItem(title: "Show", action: #selector(showWindowFromStatusItem), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let launchMinimizedItem = NSMenuItem(
            title: "Launch Minimized",
            action: #selector(toggleLaunchMinimized),
            keyEquivalent: ""
        )
        launchMinimizedItem.target = self
        menu.addItem(launchMinimizedItem)

        let launchAtLoginItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.launchAtLoginItem = launchAtLoginItem
        self.launchMinimizedItem = launchMinimizedItem
        updateLaunchAtLoginMenuItem()
        updateLaunchMinimizedMenuItem()
    }

    private func showWindow() {
        guard let window else {
            return
        }

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideWindow() {
        window?.orderOut(nil)
        updateActivationPolicy()
    }

    private func toggleWindow() {
        if window?.isVisible == true {
            hideWindow()
        } else {
            showWindow()
        }
    }

    private func updateActivationPolicy() {
        let hasVisibleWindow = [window, keySwapperWindow].contains { $0?.isVisible == true }
        NSApp.setActivationPolicy(hasVisibleWindow ? .regular : .accessory)
    }

    private func updateLaunchMinimizedMenuItem() {
        launchMinimizedItem?.state = shouldShowWindowAtLaunch ? .off : .on
    }

    private func updateLaunchAtLoginMenuItem() {
        guard let launchAtLoginItem else {
            return
        }

        if #available(macOS 13.0, *) {
            launchAtLoginItem.title = "Start at Login"
            launchAtLoginItem.isEnabled = true
            launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } else {
            launchAtLoginItem.title = "Start at Login (requires macOS 13)"
            launchAtLoginItem.isEnabled = false
            launchAtLoginItem.state = .off
        }
    }

    @objc private func showWindowFromStatusItem() {
        showWindow()
    }

    @objc private func showWindowFromNotification() {
        showWindow()
    }

    @objc private func toggleWindowFromNotification() {
        toggleWindow()
    }

    @objc private func showKeySwapperWindowFromNotification() {
        guard let keySwapperWindow else {
            return
        }

        NSApp.setActivationPolicy(.regular)
        keySwapperWindow.center()
        keySwapperWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLaunchMinimized() {
        shouldShowWindowAtLaunch.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else {
            return
        }

        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Unable to update launch-at-login state: %@", String(describing: error))
        }

        updateLaunchAtLoginMenuItem()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
