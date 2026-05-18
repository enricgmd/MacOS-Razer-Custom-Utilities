import AppKit
import Foundation
import IOKit.hid

final class RawKeyboardEventMonitor {
    var onEvent: ((String) -> Void)?

    private static let vendorID = 0x1532
    private static let productID = 0x0293

    private var hidManager: IOHIDManager?
    private var keyDownSuppressor: Any?

    func start() {
        stop()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, result, sender, value in
                RawKeyboardEventMonitor.handleHIDValue(
                    context: context,
                    result: result,
                    sender: sender,
                    value: value
                )
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            onEvent?(String(format: "[dev] unable to open BlackWidow HID manager 0x%08X", status))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            return
        }

        hidManager = manager
        keyDownSuppressor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) {
                return event
            }
            return nil
        }
    }

    func stop() {
        if let keyDownSuppressor {
            NSEvent.removeMonitor(keyDownSuppressor)
        }
        keyDownSuppressor = nil

        if let hidManager {
            IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        hidManager = nil
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let cookie = IOHIDElementGetCookie(element)
        let integerValue = IOHIDValueGetIntegerValue(value)
        let keyPart = keyboardUsageName(for: usagePage, usage: usage)
            .map { " key=\($0)" } ?? ""

        append(
            "page=\(hex(usagePage)) usage=\(hex(usage))\(keyPart) cookie=\(hexCookie(cookie)) value=\(integerValue)"
        )
    }

    private func append(_ event: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    private func keyboardUsageName(for usagePage: UInt32, usage: UInt32) -> String? {
        guard usagePage == 0x07 else {
            return nil
        }

        if (0x04...0x1D).contains(usage) {
            let scalar = UnicodeScalar(UInt8(ascii: "A") + UInt8(usage - 0x04))
            return String(Character(scalar))
        }

        if (0x1E...0x26).contains(usage) {
            return String(usage - 0x1D)
        }

        switch usage {
        case 0x27:
            return "0"
        case 0x28:
            return "return"
        case 0x29:
            return "escape"
        case 0x2A:
            return "delete"
        case 0x2B:
            return "tab"
        case 0x2C:
            return "space"
        case 0x39:
            return "caps-lock"
        case 0x3A...0x45:
            return "F\(usage - 0x39)"
        case 0x68...0x73:
            return "F\(usage - 0x5B)"
        case 0xE0:
            return "left-control"
        case 0xE1:
            return "left-shift"
        case 0xE2:
            return "left-option"
        case 0xE3:
            return "left-cmd"
        case 0xE4:
            return "right-control"
        case 0xE5:
            return "right-shift"
        case 0xE6:
            return "right-option"
        case 0xE7:
            return "right-cmd"
        default:
            return nil
        }
    }

    private func hex(_ value: UInt32) -> String {
        String(format: "0x%02X", value)
    }

    private func hexCookie(_ value: IOHIDElementCookie) -> String {
        String(format: "0x%08X", value)
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

        let monitor = Unmanaged<RawKeyboardEventMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handleHIDValue(value)
    }
}
