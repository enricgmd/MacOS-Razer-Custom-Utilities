import Foundation
import IOKit.hid

struct HIDElementSummary {
    let elementCount: Int
    let usagePages: [Int]
    let reportIDs: [Int]

    var vendorDefinedUsagePages: [Int] {
        usagePages.filter { $0 >= 0xFF00 }
    }

    var role: String {
        let hasKeyboard = usagePages.contains(0x07)
        let hasMouse = usagePages.contains(0x01) && usagePages.contains(0x09)
        let hasConsumer = usagePages.contains(0x0C)
        let hasVendor = !vendorDefinedUsagePages.isEmpty

        if hasMouse && hasConsumer && hasVendor {
            return "mouse+consumer+vendor"
        }

        if hasMouse && hasVendor {
            return "mouse+vendor"
        }

        if hasMouse {
            return "mouse"
        }

        switch (hasKeyboard, hasConsumer, hasVendor) {
        case (true, true, true):
            return "keyboard+consumer+vendor"
        case (true, true, false):
            return "keyboard+consumer"
        case (true, false, true):
            return "keyboard+vendor"
        case (false, true, true):
            return "consumer+vendor"
        case (true, false, false):
            return "keyboard"
        case (false, true, false):
            return "consumer-control"
        case (false, false, true):
            return "vendor-defined"
        default:
            return "generic-hid"
        }
    }

    var usagePagesDescription: String {
        if usagePages.isEmpty {
            return "-"
        }

        return usagePages.map(usagePageName).joined(separator: ",")
    }

    var reportIDsDescription: String {
        if reportIDs.isEmpty {
            return "0"
        }

        return reportIDs.map(String.init).joined(separator: ",")
    }
}

struct HIDDeviceDescriptor {
    let device: IOHIDDevice
    let product: String
    let manufacturer: String
    let vendorID: Int
    let productID: Int
    let transport: String
    let usagePage: Int
    let usage: Int
    let maxInputReportSize: Int
    let maxOutputReportSize: Int
    let maxFeatureReportSize: Int
    let locationID: Int
    let elementSummary: HIDElementSummary

    var physicalDeviceKey: String {
        String(format: "%04X:%04X:%08X", vendorID, productID, locationID)
    }

    var shortName: String {
        if product.isEmpty {
            return String(format: "%04X:%04X", vendorID, productID)
        }
        return String(format: "%04X:%04X %@", vendorID, productID, product)
    }

    var matchesKeyboardProfile: Bool {
        if usagePage == 0x01 && (usage == 0x06 || usage == 0x07) {
            return true
        }

        if usagePage == 0x0C && usage == 0x01 {
            return true
        }

        return false
    }

    var listLine: String {
        let usageDescription = String(format: "usagePage=0x%02X usage=0x%02X", usagePage, usage)
        let reportDescription = "maxReport=\(maxInputReportSize)"
        let locationDescription = String(format: "location=0x%08X", locationID)
        let roleDescription = "role=\(elementSummary.role)"
        let pageDescription = "pages=\(elementSummary.usagePagesDescription)"
        let reportIDsDescription = "reportIDs=\(elementSummary.reportIDsDescription)"

        return [
            shortName,
            "manufacturer=\(manufacturer.isEmpty ? "-" : manufacturer)",
            "transport=\(transport.isEmpty ? "-" : transport)",
            roleDescription,
            usageDescription,
            pageDescription,
            reportIDsDescription,
            reportDescription,
            locationDescription
        ].joined(separator: "  ")
    }

    static func from(device: IOHIDDevice) -> HIDDeviceDescriptor {
        HIDDeviceDescriptor(
            device: device,
            product: stringProperty(kIOHIDProductKey as CFString, on: device),
            manufacturer: stringProperty(kIOHIDManufacturerKey as CFString, on: device),
            vendorID: intProperty(kIOHIDVendorIDKey as CFString, on: device),
            productID: intProperty(kIOHIDProductIDKey as CFString, on: device),
            transport: stringProperty(kIOHIDTransportKey as CFString, on: device),
            usagePage: intProperty(kIOHIDPrimaryUsagePageKey as CFString, on: device),
            usage: intProperty(kIOHIDPrimaryUsageKey as CFString, on: device),
            maxInputReportSize: max(1, intProperty(kIOHIDMaxInputReportSizeKey as CFString, on: device)),
            maxOutputReportSize: max(0, intProperty(kIOHIDMaxOutputReportSizeKey as CFString, on: device)),
            maxFeatureReportSize: max(0, intProperty(kIOHIDMaxFeatureReportSizeKey as CFString, on: device)),
            locationID: intProperty(kIOHIDLocationIDKey as CFString, on: device),
            elementSummary: summarizeElements(on: device)
        )
    }
}

private func stringProperty(_ key: CFString, on device: IOHIDDevice) -> String {
    guard let value = IOHIDDeviceGetProperty(device, key) else {
        return ""
    }

    if let stringValue = value as? String {
        return stringValue
    }

    if let stringValue = value as? NSString {
        return stringValue as String
    }

    return ""
}

private func intProperty(_ key: CFString, on device: IOHIDDevice) -> Int {
    guard let value = IOHIDDeviceGetProperty(device, key) else {
        return 0
    }

    if let numberValue = value as? NSNumber {
        return numberValue.intValue
    }

    return 0
}

private func summarizeElements(on device: IOHIDDevice) -> HIDElementSummary {
    guard let values = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [Any] else {
        return HIDElementSummary(elementCount: 0, usagePages: [], reportIDs: [])
    }

    var usagePages = Set<Int>()
    var reportIDs = Set<Int>()

    for value in values {
        let element = value as! IOHIDElement
        usagePages.insert(Int(IOHIDElementGetUsagePage(element)))
        reportIDs.insert(Int(IOHIDElementGetReportID(element)))
    }

    return HIDElementSummary(
        elementCount: values.count,
        usagePages: usagePages.sorted(),
        reportIDs: reportIDs.sorted()
    )
}

private func usagePageName(_ usagePage: Int) -> String {
    switch usagePage {
    case 0x01:
        return "0x01(GenericDesktop)"
    case 0x07:
        return "0x07(Keyboard)"
    case 0x08:
        return "0x08(LEDs)"
    case 0x09:
        return "0x09(Button)"
    case 0x0C:
        return "0x0C(Consumer)"
    case let page where page >= 0xFF00:
        return String(format: "0x%04X(Vendor)", page)
    default:
        return String(format: "0x%02X", usagePage)
    }
}
