import Foundation
import IOKit.hid

enum DeathAdderMacroListenerError: Error, CustomStringConvertible {
    case noMatchingDevices
    case noInputReportInterface
    case openFailed(String, IOReturn)

    var description: String {
        switch self {
        case .noMatchingDevices:
            return "No matching DeathAdder V2 HID devices found."
        case .noInputReportInterface:
            return "No DeathAdder V2 HID interface advertises report ID 4 input reports."
        case .openFailed(let device, let status):
            return String(format: "Unable to open %@ for DeathAdder V2 input reports (0x%08X).", device, status)
        }
    }
}

final class DeathAdderMacroListener {
    private final class Registration {
        let descriptor: HIDDeviceDescriptor
        let buffer: UnsafeMutablePointer<UInt8>
        let bufferLength: CFIndex
        let dateFormatter: DateFormatter
        var activeCodes = Set<UInt8>()

        init(descriptor: HIDDeviceDescriptor) {
            self.descriptor = descriptor
            self.bufferLength = CFIndex(max(1, descriptor.maxInputReportSize))
            self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(bufferLength))
            self.buffer.initialize(repeating: 0, count: Int(bufferLength))
            self.dateFormatter = DateFormatter()
            self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
        }

        deinit {
            IOHIDDeviceUnscheduleFromRunLoop(descriptor.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            buffer.deinitialize(count: Int(bufferLength))
            buffer.deallocate()
        }
    }

    private let options: CLIOptions
    private let lister: HIDDeviceLister

    init(options: CLIOptions) throws {
        self.options = options
        self.lister = try HIDDeviceLister(options: options)
    }

    func start() throws {
        let controller = try RazerMacroController(options: options)
        try controller.enable()

        let devices = lister.filteredDevices()
        guard !devices.isEmpty else {
            throw DeathAdderMacroListenerError.noMatchingDevices
        }

        let groups = Dictionary(grouping: devices, by: \.physicalDeviceKey)
        guard let key = groups.keys.sorted(by: deathAdderDeviceGroupSort(groups)).first,
              let group = groups[key],
              !group.isEmpty
        else {
            throw DeathAdderMacroListenerError.noMatchingDevices
        }

        var registrations: [Registration] = []
        for (offset, descriptor) in group.enumerated() where isDeathAdderMacroInputCandidate(descriptor) {
            var openMode = "seize"
            var status = IOHIDDeviceOpen(descriptor.device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
            if status != kIOReturnSuccess {
                print(String(format: "Seize open failed for %@ (0x%08X); falling back to shared IOHID open.", descriptor.shortName, status))
                openMode = "shared"
                status = IOHIDDeviceOpen(descriptor.device, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            guard status == kIOReturnSuccess else {
                throw DeathAdderMacroListenerError.openFailed(descriptor.shortName, status)
            }

            let registration = Registration(descriptor: descriptor)
            IOHIDDeviceScheduleWithRunLoop(descriptor.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(
                descriptor.device,
                registration.buffer,
                registration.bufferLength,
                { context, result, sender, type, reportID, report, reportLength in
                    DeathAdderMacroListener.handleInputReport(
                        context: context,
                        result: result,
                        sender: sender,
                        type: type,
                        reportID: reportID,
                        report: report,
                        reportLength: reportLength
                    )
                },
                Unmanaged.passUnretained(registration).toOpaque()
            )

            registrations.append(registration)
            print("Attached DeathAdder macro candidate iface=\(offset + 1)/\(group.count) role=\(descriptor.elementSummary.role) maxIn=\(descriptor.maxInputReportSize) reportIDs=\(descriptor.elementSummary.reportIDsDescription) open=\(openMode)")
        }

        guard !registrations.isEmpty else {
            throw DeathAdderMacroListenerError.noInputReportInterface
        }

        print("Listening for DeathAdder V2 macro reports. Expected reportID=4, len=16, endpoint 0x82 in the Windows capture. Press Ctrl-C to stop.")
        while true {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, false)
        }
    }

    private static func handleInputReport(
        context: UnsafeMutableRawPointer?,
        result: IOReturn,
        sender: UnsafeMutableRawPointer?,
        type: IOHIDReportType,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>?,
        reportLength: CFIndex
    ) {
        guard result == kIOReturnSuccess,
              type == kIOHIDReportTypeInput,
              reportID == 4,
              let context = context,
              let report = report,
              reportLength >= 2
        else {
            return
        }

        let registration = Unmanaged<Registration>.fromOpaque(context).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: UnsafePointer(report), count: Int(reportLength)))
        let timestamp = registration.dateFormatter.string(from: Date())
        let reportedCodes = Set(bytes.dropFirst().filter { deathAdderCodeName(for: $0) != nil })

        print("[deathadder-report] \(timestamp) ifaceRole=\(registration.descriptor.elementSummary.role) len=\(reportLength) bytes=\(hexString(from: bytes))")

        for releasedCode in registration.activeCodes.subtracting(reportedCodes).sorted() {
            print("[deathadder-up]   \(timestamp) \(deathAdderCodeName(for: releasedCode) ?? "unknown") code=0x\(String(format: "%02X", releasedCode))")
        }

        for pressedCode in reportedCodes.subtracting(registration.activeCodes).sorted() {
            print("[deathadder-down] \(timestamp) \(deathAdderCodeName(for: pressedCode) ?? "unknown") code=0x\(String(format: "%02X", pressedCode))")
        }

        registration.activeCodes = reportedCodes
    }
}

private func isDeathAdderMacroInputCandidate(_ descriptor: HIDDeviceDescriptor) -> Bool {
    descriptor.maxInputReportSize >= 16 && descriptor.elementSummary.reportIDs.contains(4)
}

private func deathAdderCodeName(for code: UInt8) -> String? {
    switch code {
    case 0x20: return "captured-button-a-code-20"
    case 0x21: return "captured-button-b-code-21"
    case 0x22: return "captured-button-a-code-22"
    case 0x23: return "captured-button-b-code-23"
    default: return nil
    }
}

private func deathAdderDeviceGroupSort(_ groups: [String: [HIDDeviceDescriptor]]) -> (String, String) -> Bool {
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

private func hexString(from bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}
