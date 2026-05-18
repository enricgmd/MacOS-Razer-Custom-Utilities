import Foundation
import IOKit.hid

enum HIDDeviceListerError: Error, CustomStringConvertible {
    case managerCreationFailed

    var description: String {
        switch self {
        case .managerCreationFailed:
            return "Unable to create IOHIDManager for device enumeration."
        }
    }
}

final class HIDDeviceLister {
    private let options: CLIOptions
    private let manager: IOHIDManager

    init(options: CLIOptions) throws {
        self.options = options
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
    }

    func renderList() -> [String] {
        let visibleDevices = filteredDevices()

        let groups = Dictionary(grouping: visibleDevices, by: \.physicalDeviceKey)
        var lines: [String] = []

        for key in groups.keys.sorted(by: deviceGroupSort(groups)) {
            guard let group = groups[key], let first = group.first else {
                continue
            }

            let header = [
                first.shortName,
                "manufacturer=\(first.manufacturer.isEmpty ? "-" : first.manufacturer)",
                "transport=\(first.transport.isEmpty ? "-" : first.transport)",
                String(format: "location=0x%08X", first.locationID),
                "interfaces=\(group.count)"
            ].joined(separator: "  ")
            lines.append(header)

            for (offset, descriptor) in group.enumerated() {
                let interfaceIndex = offset + 1
                lines.append("  \(interfaceLine(for: descriptor, index: interfaceIndex, total: group.count))")
            }
        }

        return lines
    }

    func filteredDevices() -> [HIDDeviceDescriptor] {
        devices()
            .filter(matchesFilters)
            .sorted(by: sortDevices)
    }

    func devices() -> [HIDDeviceDescriptor] {
        guard let devices = IOHIDManagerCopyDevices(manager) as NSSet? else {
            return []
        }

        return devices.compactMap { value in
            HIDDeviceDescriptor.from(device: value as! IOHIDDevice)
        }
    }

    private func matchesFilters(_ descriptor: HIDDeviceDescriptor) -> Bool {
        if let vendorID = options.vendorID, descriptor.vendorID != vendorID {
            return false
        }

        if let productID = options.productID, descriptor.productID != productID {
            return false
        }

        if options.keyboardOnly && !descriptor.matchesKeyboardProfile {
            return false
        }

        return true
    }

    private func sortDevices(_ lhs: HIDDeviceDescriptor, _ rhs: HIDDeviceDescriptor) -> Bool {
        if lhs.vendorID != rhs.vendorID {
            return lhs.vendorID < rhs.vendorID
        }

        if lhs.productID != rhs.productID {
            return lhs.productID < rhs.productID
        }

        if lhs.locationID != rhs.locationID {
            return lhs.locationID < rhs.locationID
        }

        if lhs.maxInputReportSize != rhs.maxInputReportSize {
            return lhs.maxInputReportSize < rhs.maxInputReportSize
        }

        if lhs.maxFeatureReportSize != rhs.maxFeatureReportSize {
            return lhs.maxFeatureReportSize < rhs.maxFeatureReportSize
        }

        if lhs.elementSummary.role != rhs.elementSummary.role {
            return lhs.elementSummary.role < rhs.elementSummary.role
        }

        return lhs.elementSummary.elementCount < rhs.elementSummary.elementCount
    }

    private func interfaceLine(for descriptor: HIDDeviceDescriptor, index: Int, total: Int) -> String {
        [
            "iface=\(index)/\(total)",
            "role=\(descriptor.elementSummary.role)",
            String(format: "primary=0x%02X/0x%02X", descriptor.usagePage, descriptor.usage),
            "pages=\(descriptor.elementSummary.usagePagesDescription)",
            "reportIDs=\(descriptor.elementSummary.reportIDsDescription)",
            "elements=\(descriptor.elementSummary.elementCount)",
            "maxIn=\(descriptor.maxInputReportSize)",
            "maxOut=\(descriptor.maxOutputReportSize)",
            "maxFeature=\(descriptor.maxFeatureReportSize)"
        ].joined(separator: "  ")
    }
}

private func deviceGroupSort(_ groups: [String: [HIDDeviceDescriptor]]) -> (String, String) -> Bool {
    { lhs, rhs in
        guard let left = groups[lhs]?.first, let right = groups[rhs]?.first else {
            return lhs < rhs
        }

        if left.vendorID != right.vendorID {
            return left.vendorID < right.vendorID
        }

        if left.productID != right.productID {
            return left.productID < right.productID
        }

        if left.locationID != right.locationID {
            return left.locationID < right.locationID
        }

        return left.product.localizedCaseInsensitiveCompare(right.product) == .orderedAscending
    }
}
