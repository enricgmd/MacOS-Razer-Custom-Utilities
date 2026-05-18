import AppKit
import ApplicationServices
import Foundation
import IOKit.hid

enum DeathAdderButtonListenerError: Error, CustomStringConvertible {
    case eventTapCreationFailed
    case hidManagerOpenFailed(IOReturn)

    var description: String {
        switch self {
        case .eventTapCreationFailed:
            return "Unable to create DeathAdder button event tap. Check Input Monitoring / Accessibility permission."
        case .hidManagerOpenFailed(let status):
            return String(format: "Unable to open DeathAdder HID manager (0x%08X).", status)
        }
    }
}

final class DeathAdderButtonListener {
    private static let vendorID = 0x1532
    private static let productID = 0x0084

    private static let topKeyNamesByVirtualKey: [Int64: String] = [
        0x69: "top-f13",
        0x6B: "top-f14"
    ]

    private static let sideButtonNamesByUsage: [UInt32: String] = [
        0x04: "side-usage-04",
        0x05: "side-usage-05"
    ]

    private let dateFormatter: DateFormatter
    private var hidManager: IOHIDManager?
    private var eventTap: CFMachPort?

    init() {
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    func start() throws {
        try startKeyboardButtonTap()
        try startSideButtonHIDMonitor()
        CFRunLoopRun()
    }

    private func startKeyboardButtonTap() throws {
        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: deathAdderButtonEventTapCallback,
            userInfo: context
        ) else {
            throw DeathAdderButtonListenerError.eventTapCreationFailed
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func startSideButtonHIDMonitor() throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, result, sender, value in
                DeathAdderButtonListener.handleHIDValue(
                    context: context,
                    result: result,
                    sender: sender,
                    value: value
                )
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            throw DeathAdderButtonListenerError.hidManagerOpenFailed(status)
        }

        self.hidManager = manager
    }

    func handleKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard let buttonName = Self.topKeyNamesByVirtualKey[keyCode] else {
            return Unmanaged.passUnretained(event)
        }

        printEvent(buttonName: buttonName, isDown: type == .keyDown)
        return nil
    }

    func handleSideButtonValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        guard usagePage == 0x09,
              let buttonName = Self.sideButtonNamesByUsage[usage] else {
            return
        }

        let integerValue = IOHIDValueGetIntegerValue(value)
        guard integerValue == 0 || integerValue == 1 else {
            return
        }

        printEvent(buttonName: buttonName, isDown: integerValue == 1)
    }

    private func printEvent(buttonName: String, isDown: Bool) {
        let timestamp = dateFormatter.string(from: Date())
        let state = isDown ? "down" : "up"
        print("[deathadder-\(state)] \(timestamp)  button=\(buttonName)")
    }

    private static func handleHIDValue(
        context: UnsafeMutableRawPointer?,
        result: IOReturn,
        sender: UnsafeMutableRawPointer?,
        value: IOHIDValue
    ) {
        guard result == kIOReturnSuccess,
              let context = context else {
            return
        }

        let listener = Unmanaged<DeathAdderButtonListener>.fromOpaque(context).takeUnretainedValue()
        listener.handleSideButtonValue(value)
    }
}

private func deathAdderButtonEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let listener = Unmanaged<DeathAdderButtonListener>.fromOpaque(userInfo).takeUnretainedValue()
    return listener.handleKeyEvent(type: type, event: event)
}
