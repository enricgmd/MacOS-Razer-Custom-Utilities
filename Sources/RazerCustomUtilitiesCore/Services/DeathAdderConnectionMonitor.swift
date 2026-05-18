import Foundation
import IOKit.hid

final class DeathAdderConnectionMonitor {
    private static let vendorID = 0x1532
    private static let productID = 0x0084

    func isConnected() -> Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            return false
        }
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return false
        }

        return !devices.isEmpty
    }
}
