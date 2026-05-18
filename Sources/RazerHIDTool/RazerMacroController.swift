import Foundation
import IOKit.hid

enum RazerMacroControllerError: Error, CustomStringConvertible {
    case noMatchingDevices
    case noFeatureReportCapableDevices
    case openFailed(String, IOReturn)
    case allReportsFailed

    var description: String {
        switch self {
        case .noMatchingDevices:
            return "No matching Razer HID devices found."
        case .noFeatureReportCapableDevices:
            return "No matching HID interface advertises a 90-byte feature report."
        case .openFailed(let device, let status):
            return String(format: "Unable to open %@ for feature reports (0x%08X).", device, status)
        case .allReportsFailed:
            return "All Razer feature report attempts failed."
        }
    }
}

final class RazerMacroController {
    private let lister: HIDDeviceLister

    init(options: CLIOptions) throws {
        self.lister = try HIDDeviceLister(options: options)
    }

    func enable() throws {
        try send([
            .setDeviceMode(mode: 0x03, parameter: 0x00),
            .setMacroLED(enabled: true)
        ], label: "macro-on")
    }

    func disable() throws {
        try send([
            .setMacroLED(enabled: false),
            .setDeviceMode(mode: 0x00, parameter: 0x00)
        ], label: "macro-off")
    }

    private func send(_ reports: [RazerReport], label: String) throws {
        let candidates = featureReportCandidates()
        guard !candidates.isEmpty else {
            throw lister.filteredDevices().isEmpty ? RazerMacroControllerError.noMatchingDevices : RazerMacroControllerError.noFeatureReportCapableDevices
        }

        var successes = 0
        for descriptor in candidates {
            let openStatus = IOHIDDeviceOpen(descriptor.device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openStatus == kIOReturnSuccess else {
                print(String(format: "Skipping %@: open failed 0x%08X", descriptor.shortName, openStatus))
                continue
            }
            defer {
                IOHIDDeviceClose(descriptor.device, IOOptionBits(kIOHIDOptionsTypeNone))
            }

            print("Trying \(label) on \(descriptor.shortName) maxFeature=\(descriptor.maxFeatureReportSize) role=\(descriptor.elementSummary.role)")
            for report in reports {
                var bytes = report.bytes
                let status = bytes.withUnsafeMutableBufferPointer { buffer -> IOReturn in
                    guard let baseAddress = buffer.baseAddress else {
                        return kIOReturnError
                    }

                    return IOHIDDeviceSetReport(
                        descriptor.device,
                        kIOHIDReportTypeFeature,
                        CFIndex(0),
                        baseAddress,
                        buffer.count
                    )
                }

                let statusText = String(format: "0x%08X", status)
                print("  \(report.name): \(statusText) bytes=\(hexString(from: bytes.prefix(16))) ... crc=\(String(format: "%02X", bytes[88]))")
                if status == kIOReturnSuccess {
                    successes += 1
                    usleep(20_000)
                }
            }
        }

        guard successes > 0 else {
            throw RazerMacroControllerError.allReportsFailed
        }
    }

    private func featureReportCandidates() -> [HIDDeviceDescriptor] {
        lister.filteredDevices()
            .filter { $0.maxFeatureReportSize >= RazerReport.length }
            .sorted {
                if $0.maxFeatureReportSize != $1.maxFeatureReportSize {
                    return $0.maxFeatureReportSize > $1.maxFeatureReportSize
                }
                return $0.elementSummary.role < $1.elementSummary.role
            }
    }
}

private struct RazerReport {
    static let length = 0x5A

    let name: String
    let bytes: [UInt8]

    static func setDeviceMode(mode: UInt8, parameter: UInt8) -> RazerReport {
        make(
            name: String(format: "set-device-mode %02X %02X", mode, parameter),
            commandClass: 0x00,
            commandID: 0x04,
            arguments: [mode, parameter]
        )
    }

    static func setMacroLED(enabled: Bool) -> RazerReport {
        make(
            name: "set-macro-mode \(enabled ? "on" : "off")",
            commandClass: 0x03,
            commandID: 0x00,
            arguments: [0x01, 0x07, enabled ? 0x01 : 0x00]
        )
    }

    private static func make(name: String, commandClass: UInt8, commandID: UInt8, arguments: [UInt8]) -> RazerReport {
        var bytes = [UInt8](repeating: 0, count: length)
        bytes[0] = 0x00
        bytes[1] = 0xFF
        bytes[4] = 0x00
        bytes[5] = UInt8(arguments.count)
        bytes[6] = commandClass
        bytes[7] = commandID

        for (offset, argument) in arguments.enumerated() {
            bytes[8 + offset] = argument
        }

        bytes[88] = bytes[2..<88].reduce(0) { $0 ^ $1 }
        bytes[89] = 0x00

        return RazerReport(name: name, bytes: bytes)
    }
}

private func hexString(from bytes: ArraySlice<UInt8>) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}
