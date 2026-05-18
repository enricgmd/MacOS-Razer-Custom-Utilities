import Foundation
import IOKit.hid

final class DeathAdderButtonModel: ObservableObject {
    private static let vendorID = 0x1532
    private static let productID = 0x0084

    private static let hotspotIDsByKeyboardUsage: [UInt32: String] = [
        0x6A: "top-front",
        0x6B: "top-rear"
    ]

    private static let hotspotIDsBySideUsage: [UInt32: String] = [
        0x04: "side-front",
        0x05: "side-rear"
    ]

    @Published private(set) var activeHotspotIDs = Set<String>()

    private let assignmentStore: ActionAssignmentStore?
    private let fKeySuppressor: DeathAdderFKeySuppressor?
    private var hidManager: IOHIDManager?

    init(
        assignmentStore: ActionAssignmentStore? = nil,
        fKeySuppressor: DeathAdderFKeySuppressor? = nil
    ) {
        self.assignmentStore = assignmentStore
        self.fKeySuppressor = fKeySuppressor
    }

    func start() {
        startButtonMonitor()
    }

    func stop() {
        if let hidManager {
            IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        hidManager = nil
        activeHotspotIDs.removeAll()
    }

    func isActive(_ hotspotID: String) -> Bool {
        activeHotspotIDs.contains(hotspotID)
    }

    private func startButtonMonitor() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { context, result, sender, value in
                DeathAdderButtonModel.handleHIDValue(
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
            NSLog("Unable to open DeathAdder V2 HID manager: 0x%08X", status)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            return
        }

        hidManager = manager
    }

    private func handleButtonValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)

        guard integerValue == 0 || integerValue == 1 else {
            return
        }

        if usagePage == 0x07 {
            fKeySuppressor?.noteDeathAdderKeyboardUsage(usage, value: integerValue)
            if let hotspotID = Self.hotspotIDsByKeyboardUsage[usage] {
                setHotspot(hotspotID, active: integerValue == 1)
            }
            return
        }

        if usagePage == 0x09,
           let hotspotID = Self.hotspotIDsBySideUsage[usage] {
            setHotspot(hotspotID, active: integerValue == 1)
        }
    }

    private func setHotspot(_ hotspotID: String, active: Bool) {
        DispatchQueue.main.async {
            if active {
                let inserted = self.activeHotspotIDs.insert(hotspotID).inserted
                if inserted {
                    self.assignmentStore?.performAssignment(for: hotspotID)
                }
            } else {
                self.activeHotspotIDs.remove(hotspotID)
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

        let model = Unmanaged<DeathAdderButtonModel>.fromOpaque(context).takeUnretainedValue()
        model.handleButtonValue(value)
    }
}
