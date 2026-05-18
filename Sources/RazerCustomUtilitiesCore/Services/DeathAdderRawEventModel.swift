import Foundation
import IOKit.hid

final class DeathAdderRawEventModel: ObservableObject {
    private static let vendorID = 0x1532
    private static let productID = 0x0084
    private static let topKeyNamesByKeyboardUsage: [UInt32: String] = [
        0x6A: "F15",
        0x6B: "F16"
    ]
    private let eventLimit = 90

    @Published private(set) var isEnabled = false
    @Published private(set) var filtersMouseNoise = true
    @Published private(set) var filtersClickAndScrollNoise = false
    @Published private(set) var events: [String] = []

    private var hidManager: IOHIDManager?

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else {
            return
        }

        isEnabled = enabled
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func setFiltersMouseNoise(_ enabled: Bool) {
        filtersMouseNoise = enabled
    }

    func setFiltersClickAndScrollNoise(_ enabled: Bool) {
        filtersClickAndScrollNoise = enabled
    }

    func stop() {
        if let hidManager {
            IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        hidManager = nil
        isEnabled = false
    }

    private func start() {
        events.removeAll()
        append("[dev] Listening for mouse raw events")
        startHIDValueMonitor()
    }

    private func startHIDValueMonitor() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, result, sender, value in
                DeathAdderRawEventModel.handleHIDValue(
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
            append(String(format: "[dev] unable to open DeathAdder HID manager 0x%08X", status))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            return
        }

        hidManager = manager
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)

        if filtersMouseNoise && isMouseMovement(usagePage: usagePage, usage: usage) {
            return
        }

        if shouldFilterClickOrScroll(usagePage: usagePage, usage: usage, value: integerValue) {
            return
        }

        if isButtonTransitionNoise(usagePage: usagePage, usage: usage, value: integerValue) {
            return
        }

        if usagePage == 0x07,
           Self.topKeyNamesByKeyboardUsage[usage] != nil,
           integerValue == 0 || integerValue == 1 {
            handleKeyboardUsage(usage: usage, value: integerValue)
            return
        }

        if usagePage == 0x09,
           let buttonName = buttonName(for: usage),
           integerValue == 0 || integerValue == 1 {
            handleButton(name: buttonName, usage: usage, value: integerValue)
            return
        }

        if usagePage == 0x01,
           let controlName = genericDesktopControlName(for: usage) {
            append("\(controlName) value=\(integerValue) page=0x01 usage=\(hex(usage))")
            return
        }

        append("page=\(hex(usagePage)) usage=\(hex(usage)) value=\(integerValue)")
    }

    private func handleKeyboardUsage(usage: UInt32, value: Int) {
        guard let keyName = Self.topKeyNamesByKeyboardUsage[usage] else {
            return
        }

        let action = value == 1 ? "down" : "up"
        append("\(action) key=\(keyName) usage=\(hex(usage))")
    }

    private func handleButton(name: String, usage: UInt32, value: Int) {
        let action = value == 1 ? "down" : "up"
        append("\(name) \(action) page=0x09 usage=\(hex(usage))")
    }

    private func isMouseMovement(usagePage: UInt32, usage: UInt32) -> Bool {
        if usagePage == 0x01 {
            return usage == 0x30 || usage == 0x31
        }

        if usagePage == 0xFF00 {
            return usage == 0x40
        }

        return false
    }

    private func shouldFilterClickOrScroll(usagePage: UInt32, usage: UInt32, value: Int) -> Bool {
        if usagePage == 0x01 && usage == 0x38 {
            return value == 0 || filtersClickAndScrollNoise
        }

        if usagePage == 0x09 && (usage == 0x01 || usage == 0x02) {
            return filtersClickAndScrollNoise
        }

        return false
    }

    private func isButtonTransitionNoise(usagePage: UInt32, usage: UInt32, value: Int) -> Bool {
        if usagePage == 0x07 {
            return Self.topKeyNamesByKeyboardUsage[usage] == nil || !(value == 0 || value == 1)
        }

        return false
    }

    private func buttonName(for usage: UInt32) -> String? {
        switch usage {
        case 0x01:
            return "left-click"
        case 0x02:
            return "right-click"
        case 0x03:
            return "middle-click"
        case 0x04:
            return "side-rear"
        case 0x05:
            return "side-front"
        default:
            return "button-\(usage)"
        }
    }

    private func genericDesktopControlName(for usage: UInt32) -> String? {
        switch usage {
        case 0x30:
            return "move-x"
        case 0x31:
            return "move-y"
        case 0x32:
            return "move-z"
        case 0x38:
            return "wheel"
        default:
            return nil
        }
    }

    private func hex(_ value: UInt32) -> String {
        String(format: "0x%02X", value)
    }

    private func append(_ event: String) {
        DispatchQueue.main.async {
            self.events.insert(event, at: 0)
            if self.events.count > self.eventLimit {
                self.events.removeLast(self.events.count - self.eventLimit)
            }
        }
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

        let model = Unmanaged<DeathAdderRawEventModel>.fromOpaque(context).takeUnretainedValue()
        model.handleHIDValue(value)
    }
}
