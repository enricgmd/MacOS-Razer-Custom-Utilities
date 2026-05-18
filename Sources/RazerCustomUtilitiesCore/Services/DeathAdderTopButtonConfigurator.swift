import Foundation
import IOKit.hid

final class DeathAdderTopButtonConfigurator {
    private static let vendorID = 0x1532
    private static let productID = 0x0084
    fileprivate static let reportLength = 0x5A
    private static let topFrontButton: UInt8 = 0x0B
    private static let topRearButton: UInt8 = 0x0C
    private static let f15Usage: UInt16 = 0x006A
    private static let f16Usage: UInt16 = 0x006B

    private let queue = DispatchQueue(label: "razer-custom-utilities.deathadder-top-button-configurator")
    private var isEnsuring = false

    func ensureDefaultAssignmentsInBackground(reason: String) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard !self.isEnsuring else {
                return
            }

            self.isEnsuring = true
            defer {
                self.isEnsuring = false
            }

            do {
                let result = try self.ensureDefaultAssignments()
                if result.reportsSent > 0 {
                    NSLog(
                        "DeathAdder top-button assignments ensured (%@): devices=%d reports=%d",
                        reason,
                        result.devicesConfigured,
                        result.reportsSent
                    )
                }
            } catch {
                NSLog("Unable to ensure DeathAdder top-button assignments (%@): %@", reason, String(describing: error))
            }
        }
    }

    private func ensureDefaultAssignments() throws -> EnsureResult {
        let reports = [
            BindingReport.mouseButton(
                slot: 0x01,
                button: Self.topFrontButton,
                keyboardUsage: Self.f15Usage,
                transactionID: 0x01
            ),
            BindingReport.mouseButton(
                slot: 0x01,
                button: Self.topRearButton,
                keyboardUsage: Self.f16Usage,
                transactionID: 0x02
            )
        ]

        let candidates = matchingDevices()
            .filter { $0.maxFeatureReportSize >= Self.reportLength }
            .sorted {
                if $0.maxFeatureReportSize != $1.maxFeatureReportSize {
                    return $0.maxFeatureReportSize > $1.maxFeatureReportSize
                }
                return $0.locationID < $1.locationID
            }

        guard !candidates.isEmpty else {
            return EnsureResult(devicesConfigured: 0, reportsSent: 0)
        }

        var devicesConfigured = 0
        var reportsSent = 0

        for candidate in candidates {
            let openStatus = IOHIDDeviceOpen(candidate.device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openStatus == kIOReturnSuccess else {
                NSLog("Skipping DeathAdder top-button assignment on %@: open failed 0x%08X", candidate.summary, openStatus)
                continue
            }
            defer {
                IOHIDDeviceClose(candidate.device, IOOptionBits(kIOHIDOptionsTypeNone))
            }

            var sentForDevice = 0
            for report in reports {
                var bytes = report.bytes
                let byteCount = bytes.count
                let status = bytes.withUnsafeMutableBufferPointer { buffer -> IOReturn in
                    guard let baseAddress = buffer.baseAddress else {
                        return kIOReturnError
                    }
                    return IOHIDDeviceSetReport(
                        candidate.device,
                        kIOHIDReportTypeFeature,
                        CFIndex(0),
                        baseAddress,
                        byteCount
                    )
                }

                guard status == kIOReturnSuccess else {
                    NSLog(
                        "DeathAdder top-button assignment failed on %@ report=%@: 0x%08X",
                        candidate.summary,
                        report.name,
                        status
                    )
                    continue
                }

                sentForDevice += 1
                reportsSent += 1
                usleep(20_000)
            }

            if sentForDevice == reports.count {
                devicesConfigured += 1
            }
        }

        return EnsureResult(devicesConfigured: devicesConfigured, reportsSent: reportsSent)
    }

    private func matchingDevices() -> [HIDCandidate] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openStatus == kIOReturnSuccess else {
            NSLog("Unable to open HID manager for DeathAdder top-button assignment: 0x%08X", openStatus)
            return []
        }
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        guard let devices = IOHIDManagerCopyDevices(manager) as NSSet? else {
            return []
        }

        return devices.compactMap { value in
            let device = value as! IOHIDDevice
            return HIDCandidate(
                device: device,
                product: stringProperty(kIOHIDProductKey, on: device) ?? "DeathAdder V2",
                locationID: intProperty(kIOHIDLocationIDKey, on: device),
                maxFeatureReportSize: intProperty(kIOHIDMaxFeatureReportSizeKey, on: device)
            )
        }
    }
}

private struct EnsureResult {
    let devicesConfigured: Int
    let reportsSent: Int
}

private struct HIDCandidate {
    let device: IOHIDDevice
    let product: String
    let locationID: Int
    let maxFeatureReportSize: Int

    var summary: String {
        String(format: "%@ location=0x%08X maxFeature=%d", product, locationID, maxFeatureReportSize)
    }
}

private struct BindingReport {
    let name: String
    let bytes: [UInt8]

    static func mouseButton(slot: UInt8, button: UInt8, keyboardUsage: UInt16, transactionID: UInt8) -> BindingReport {
        var bytes = [UInt8](repeating: 0, count: DeathAdderTopButtonConfigurator.reportLength)
        bytes[0] = 0x00
        bytes[1] = transactionID
        bytes[5] = 0x0A
        bytes[6] = 0x02
        bytes[7] = 0x0C
        bytes[8] = slot
        bytes[9] = button
        bytes[10] = 0x00
        bytes[11] = 0x02
        bytes[12] = 0x02
        bytes[13] = UInt8((keyboardUsage >> 8) & 0xFF)
        bytes[14] = UInt8(keyboardUsage & 0xFF)
        bytes[88] = bytes[2..<88].reduce(0) { $0 ^ $1 }
        bytes[89] = 0x00

        return BindingReport(
            name: String(format: "button-0x%02X->usage-0x%04X", button, keyboardUsage),
            bytes: bytes
        )
    }
}

private func intProperty(_ key: String, on device: IOHIDDevice) -> Int {
    guard let value = IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber else {
        return 0
    }
    return value.intValue
}

private func stringProperty(_ key: String, on device: IOHIDDevice) -> String? {
    IOHIDDeviceGetProperty(device, key as CFString) as? String
}
