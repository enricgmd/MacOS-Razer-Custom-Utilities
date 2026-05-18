import Foundation
import IOKit.hid

enum RazerMacroListenerError: Error, CustomStringConvertible {
    case noMatchingDevices
    case openFailed(String, IOReturn)

    var description: String {
        switch self {
        case .noMatchingDevices:
            return "No matching Razer HID devices found."
        case .openFailed(let device, let status):
            return String(format: "Unable to open %@ for macro input reports (0x%08X).", device, status)
        }
    }
}

final class RazerMacroListener {
    private final class Registration {
        let descriptor: HIDDeviceDescriptor
        let buffer: UnsafeMutablePointer<UInt8>
        let bufferLength: CFIndex
        let dateFormatter: DateFormatter
        var activeMacroCodes = Set<UInt8>()

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
            throw RazerMacroListenerError.noMatchingDevices
        }

        let groups = Dictionary(grouping: devices, by: \.physicalDeviceKey)
        guard let key = groups.keys.sorted(by: macroDeviceGroupSort(groups)).first,
              let group = groups[key],
              !group.isEmpty
        else {
            throw RazerMacroListenerError.noMatchingDevices
        }

        var registrations: [Registration] = []
        for descriptor in group where isMacroInputCandidate(descriptor) {
            let status = IOHIDDeviceOpen(descriptor.device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard status == kIOReturnSuccess else {
                throw RazerMacroListenerError.openFailed(descriptor.shortName, status)
            }

            let registration = Registration(descriptor: descriptor)
            IOHIDDeviceScheduleWithRunLoop(descriptor.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(
                descriptor.device,
                registration.buffer,
                registration.bufferLength,
                { context, result, sender, type, reportID, report, reportLength in
                    RazerMacroListener.handleInputReport(
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
        }

        guard !registrations.isEmpty else {
            throw RazerMacroListenerError.noMatchingDevices
        }

        print("Listening for Razer macro keys M1-M6. Press Ctrl-C to stop.")
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
        guard bytes.first == 0x04 else {
            return
        }

        let timestamp = registration.dateFormatter.string(from: Date())
        let reportedCodes = Set(bytes.dropFirst().filter { macroName(for: $0) != nil })

        for releasedCode in registration.activeMacroCodes.subtracting(reportedCodes).sorted() {
            print("[macro-up]   \(timestamp)  \(macroName(for: releasedCode) ?? "M?")  code=0x\(String(format: "%02X", releasedCode))  mapsTo=\(functionKeyName(for: releasedCode))")
        }

        for pressedCode in reportedCodes.subtracting(registration.activeMacroCodes).sorted() {
            print("[macro-down] \(timestamp)  \(macroName(for: pressedCode) ?? "M?")  code=0x\(String(format: "%02X", pressedCode))  mapsTo=\(functionKeyName(for: pressedCode))")
        }

        registration.activeMacroCodes = reportedCodes
    }
}

private func isMacroInputCandidate(_ descriptor: HIDDeviceDescriptor) -> Bool {
    descriptor.maxInputReportSize >= 8 && descriptor.elementSummary.reportIDs.contains(4)
}

private func macroName(for code: UInt8) -> String? {
    guard (0x20...0x25).contains(code) else {
        return nil
    }

    return "M\(Int(code - 0x20) + 1)"
}

private func functionKeyName(for code: UInt8) -> String {
    guard (0x20...0x25).contains(code) else {
        return "-"
    }

    return "F\(Int(code - 0x20) + 13)"
}

private func macroDeviceGroupSort(_ groups: [String: [HIDDeviceDescriptor]]) -> (String, String) -> Bool {
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
