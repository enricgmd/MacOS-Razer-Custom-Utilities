import Foundation
import IOKit.hid

enum HIDReportDescriptorDumperError: Error, CustomStringConvertible {
    case noMatchingDevices
    case interfaceNotFound(Int)
    case descriptorUnavailable(String)

    var description: String {
        switch self {
        case .noMatchingDevices:
            return "No matching HID devices found for the requested vendor/product."
        case .interfaceNotFound(let index):
            return "Interface \(index) was not found for the requested device."
        case .descriptorUnavailable(let device):
            return "No HID report descriptor available for \(device)."
        }
    }
}

final class HIDReportDescriptorDumper {
    private let options: CLIOptions
    private let lister: HIDDeviceLister

    init(options: CLIOptions) throws {
        self.options = options
        self.lister = try HIDDeviceLister(options: options)
    }

    func dump() throws {
        let devices = lister.filteredDevices()
        guard !devices.isEmpty else {
            throw HIDReportDescriptorDumperError.noMatchingDevices
        }

        let groups = Dictionary(grouping: devices, by: \.physicalDeviceKey)
        guard let interfaceIndex = options.interfaceIndex else {
            throw HIDReportDescriptorDumperError.interfaceNotFound(0)
        }

        var selected: HIDDeviceDescriptor?
        for key in groups.keys.sorted(by: dumpDeviceGroupSort(groups)) {
            guard let group = groups[key], interfaceIndex <= group.count else {
                continue
            }
            selected = group[interfaceIndex - 1]
            break
        }

        guard let descriptor = selected else {
            throw HIDReportDescriptorDumperError.interfaceNotFound(interfaceIndex)
        }

        guard let property = IOHIDDeviceGetProperty(descriptor.device, kIOHIDReportDescriptorKey as CFString) else {
            throw HIDReportDescriptorDumperError.descriptorUnavailable(descriptor.shortName)
        }

        let data = property as? Data

        guard let descriptorData = data else {
            throw HIDReportDescriptorDumperError.descriptorUnavailable(descriptor.shortName)
        }

        print("Descriptor for \(descriptor.shortName) iface=\(interfaceIndex) role=\(descriptor.elementSummary.role)")
        print("length=\(descriptorData.count) bytes")
        print("")
        print(hexDump(descriptorData))
        print("")
        print("Parsed items:")
        parsedItems(from: descriptorData).forEach { print($0) }
    }

    private func hexDump(_ data: Data) -> String {
        let bytes = Array(data)
        var lines: [String] = []

        for offset in stride(from: 0, to: bytes.count, by: 16) {
            let chunk = Array(bytes[offset ..< min(offset + 16, bytes.count)])
            let hex = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
            lines.append(String(format: "%04X  %@", offset, hex))
        }

        return lines.joined(separator: "\n")
    }

    private func parsedItems(from data: Data) -> [String] {
        let bytes = Array(data)
        var index = 0
        var lines: [String] = []

        while index < bytes.count {
            let prefix = bytes[index]

            if prefix == 0xFE {
                if index + 2 >= bytes.count { break }
                let size = Int(bytes[index + 1])
                let longTag = bytes[index + 2]
                let payloadEnd = min(index + 3 + size, bytes.count)
                let payload = Array(bytes[(index + 3) ..< payloadEnd])
                lines.append(String(format: "%04X  long tag=0x%02X size=%d data=%@", index, longTag, size, hexString(payload)))
                index = payloadEnd
                continue
            }

            let sizeCode = Int(prefix & 0x03)
            let size = sizeCode == 3 ? 4 : sizeCode
            let typeCode = Int((prefix >> 2) & 0x03)
            let tagCode = Int((prefix >> 4) & 0x0F)
            let payloadStart = index + 1
            let payloadEnd = min(payloadStart + size, bytes.count)
            let payload = Array(bytes[payloadStart ..< payloadEnd])
            let value = littleEndianValue(payload)

            lines.append(
                String(
                    format: "%04X  %@  %@  size=%d  value=%@  data=%@",
                    index,
                    itemTypeName(typeCode),
                    itemTagName(typeCode, tagCode),
                    size,
                    value.map(String.init) ?? "-",
                    hexString(payload)
                )
            )

            index = payloadEnd
        }

        return lines
    }

    private func littleEndianValue(_ payload: [UInt8]) -> Int? {
        guard !payload.isEmpty else { return nil }
        var result = 0
        for (offset, byte) in payload.enumerated() {
            result |= Int(byte) << (offset * 8)
        }
        return result
    }

    private func itemTypeName(_ type: Int) -> String {
        switch type {
        case 0: return "main"
        case 1: return "global"
        case 2: return "local"
        default: return "reserved"
        }
    }

    private func itemTagName(_ type: Int, _ tag: Int) -> String {
        switch (type, tag) {
        case (0, 8): return "input"
        case (0, 9): return "output"
        case (0, 10): return "collection"
        case (0, 11): return "feature"
        case (0, 12): return "end-collection"
        case (1, 0): return "usage-page"
        case (1, 1): return "logical-min"
        case (1, 2): return "logical-max"
        case (1, 3): return "physical-min"
        case (1, 4): return "physical-max"
        case (1, 5): return "unit-exponent"
        case (1, 6): return "unit"
        case (1, 7): return "report-size"
        case (1, 8): return "report-id"
        case (1, 9): return "report-count"
        case (1, 10): return "push"
        case (1, 11): return "pop"
        case (2, 0): return "usage"
        case (2, 1): return "usage-min"
        case (2, 2): return "usage-max"
        case (2, 3): return "designator-index"
        case (2, 4): return "designator-min"
        case (2, 5): return "designator-max"
        case (2, 7): return "string-index"
        case (2, 8): return "string-min"
        case (2, 9): return "string-max"
        case (2, 10): return "delimiter"
        default: return String(format: "tag-0x%X", tag)
        }
    }

    private func hexString(_ payload: [UInt8]) -> String {
        if payload.isEmpty { return "-" }
        return payload.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

private func dumpDeviceGroupSort(_ groups: [String: [HIDDeviceDescriptor]]) -> (String, String) -> Bool {
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
