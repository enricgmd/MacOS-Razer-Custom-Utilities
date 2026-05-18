import Foundation
import IOKit.hid

enum HIDInterfaceProbeError: Error, CustomStringConvertible {
    case noMatchingDevices
    case interfaceNotFound(Int)
    case deviceOpenFailed(String, IOReturn)
    case queueCreationFailed(String)

    var description: String {
        switch self {
        case .noMatchingDevices:
            return "No matching HID devices found for the requested vendor/product."
        case .interfaceNotFound(let index):
            return "Interface \(index) was not found for the requested device."
        case .deviceOpenFailed(let device, let status):
            return String(format: "Unable to open %@ (0x%08X).", device, status)
        case .queueCreationFailed(let device):
            return "Unable to create IOHIDQueue for \(device)."
        }
    }
}

final class HIDInterfaceProbe {
    enum EventFilter {
        case none
        case deathAdderV2SpecialOnly
        case deathAdderV2Audit
    }

    final class Registration {
        let descriptor: HIDDeviceDescriptor
        let queue: IOHIDQueue
        let callbackReportBuffer: UnsafeMutablePointer<UInt8>
        let featureReportBuffer: UnsafeMutablePointer<UInt8>
        let reportBufferLength: CFIndex
        let reportIDs: [Int]
        let eventFilter: EventFilter
        var lastFeatureReports: [Int: [UInt8]]
        var lastSpecialMouseButtonMask: UInt8
        var lastMouseAuditSignature: [UInt8]
        let dateFormatter: DateFormatter

        init(descriptor: HIDDeviceDescriptor, eventFilter: EventFilter) throws {
            self.descriptor = descriptor
            self.eventFilter = eventFilter
            guard let queue = IOHIDQueueCreate(kCFAllocatorDefault, descriptor.device, 2048, IOOptionBits(kIOHIDOptionsTypeNone)) else {
                throw HIDInterfaceProbeError.queueCreationFailed(descriptor.shortName)
            }
            self.queue = queue
            self.reportBufferLength = CFIndex(max(1, descriptor.maxInputReportSize))
            self.callbackReportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(reportBufferLength))
            self.featureReportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(reportBufferLength))
            self.callbackReportBuffer.initialize(repeating: 0, count: Int(reportBufferLength))
            self.featureReportBuffer.initialize(repeating: 0, count: Int(reportBufferLength))
            self.reportIDs = descriptor.elementSummary.reportIDs.isEmpty ? [0] : descriptor.elementSummary.reportIDs
            self.lastFeatureReports = [:]
            self.lastSpecialMouseButtonMask = 0
            self.lastMouseAuditSignature = []
            self.dateFormatter = DateFormatter()
            self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
        }

        deinit {
            IOHIDDeviceUnscheduleFromRunLoop(descriptor.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDQueueStop(queue)
            callbackReportBuffer.deinitialize(count: Int(reportBufferLength))
            callbackReportBuffer.deallocate()
            featureReportBuffer.deinitialize(count: Int(reportBufferLength))
            featureReportBuffer.deallocate()
        }
    }

    private let options: CLIOptions
    private let lister: HIDDeviceLister
    private let dateFormatter: DateFormatter

    init(options: CLIOptions) throws {
        self.options = options
        self.lister = try HIDDeviceLister(options: options)
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    func start() throws {
        let devices = lister.filteredDevices()
        guard !devices.isEmpty else {
            throw HIDInterfaceProbeError.noMatchingDevices
        }

        let groups = Dictionary(grouping: devices, by: \.physicalDeviceKey)
        guard let interfaceIndex = options.interfaceIndex else {
            throw HIDInterfaceProbeError.interfaceNotFound(0)
        }

        var selected: HIDDeviceDescriptor?
        for key in groups.keys.sorted(by: probeDeviceGroupSort(groups)) {
            guard let group = groups[key], interfaceIndex <= group.count else {
                continue
            }
            selected = group[interfaceIndex - 1]
            break
        }

        guard let descriptor = selected else {
            throw HIDInterfaceProbeError.interfaceNotFound(interfaceIndex)
        }

        let status = IOHIDDeviceOpen(descriptor.device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else {
            throw HIDInterfaceProbeError.deviceOpenFailed(descriptor.shortName, status)
        }

        let registration = try Registration(descriptor: descriptor, eventFilter: .none)
        configureQueue(for: registration)
        configureInputReportCallback(for: registration)
        primeReportBaselines(for: registration)

        print("Attached to \(descriptor.shortName) iface=\(interfaceIndex) role=\(descriptor.elementSummary.role) pages=\(descriptor.elementSummary.usagePagesDescription)")
        print("Listening for HID value/input-report/feature-report changes on the selected interface. Press Ctrl-C to stop.")

        while true {
            drainQueue(for: registration)
            pollFeatureReports(for: registration)
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.01, false)
        }
    }

    func startAllInterfaces(eventFilter: EventFilter = .none) throws {
        let devices = lister.filteredDevices()
        guard !devices.isEmpty else {
            throw HIDInterfaceProbeError.noMatchingDevices
        }

        let groups = Dictionary(grouping: devices, by: \.physicalDeviceKey)
        guard let key = groups.keys.sorted(by: probeDeviceGroupSort(groups)).first,
              let group = groups[key],
              !group.isEmpty
        else {
            throw HIDInterfaceProbeError.noMatchingDevices
        }

        var registrations: [Registration] = []
        for (offset, descriptor) in group.enumerated() {
            let status = IOHIDDeviceOpen(descriptor.device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard status == kIOReturnSuccess else {
                throw HIDInterfaceProbeError.deviceOpenFailed(descriptor.shortName, status)
            }

            let registration = try Registration(descriptor: descriptor, eventFilter: eventFilter)
            configureQueue(for: registration)
            configureInputReportCallback(for: registration)
            registrations.append(registration)

            print("Attached to \(descriptor.shortName) iface=\(offset + 1)/\(group.count) role=\(descriptor.elementSummary.role) maxReport=\(descriptor.maxInputReportSize) pages=\(descriptor.elementSummary.usagePagesDescription)")
        }

        switch eventFilter {
        case .none:
            print("Listening for HID value/input-report changes on all interfaces. Press Ctrl-C to stop.")
        case .deathAdderV2SpecialOnly:
            print("Listening for DeathAdder V2 special events only. Filtering movement, wheel, left click, and right click. Press Ctrl-C to stop.")
        case .deathAdderV2Audit:
            print("Auditing DeathAdder V2 events on all interfaces. Filtering movement, wheel, left click, and right click, but keeping vendor-defined mouse fields. Press Ctrl-C to stop.")
        }

        while true {
            for registration in registrations {
                drainQueue(for: registration)
            }
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.01, false)
        }
    }

    private func configureQueue(for registration: Registration) {
        for element in inputElements(on: registration.descriptor.device) {
            IOHIDQueueAddElement(registration.queue, element)
        }
        IOHIDQueueStart(registration.queue)
    }

    private func configureInputReportCallback(for registration: Registration) {
        IOHIDDeviceScheduleWithRunLoop(registration.descriptor.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(
            registration.descriptor.device,
            registration.callbackReportBuffer,
            registration.reportBufferLength,
            { context, result, sender, type, reportID, report, reportLength in
                HIDInterfaceProbe.handleInputReport(
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
    }

    private func primeReportBaselines(for registration: Registration) {
        for reportID in registration.reportIDs {
            var featureReportLength = registration.reportBufferLength
            registration.featureReportBuffer.initialize(repeating: 0, count: Int(registration.reportBufferLength))
            let featureStatus = IOHIDDeviceGetReport(
                registration.descriptor.device,
                kIOHIDReportTypeFeature,
                CFIndex(reportID),
                registration.featureReportBuffer,
                &featureReportLength
            )
            if featureStatus == kIOReturnSuccess {
                registration.lastFeatureReports[reportID] = byteArray(from: registration.featureReportBuffer, length: Int(featureReportLength))
            }
        }
    }

    private func drainQueue(for registration: Registration) {
        while let value = IOHIDQueueCopyNextValueWithTimeout(registration.queue, 0) {
            let element = IOHIDValueGetElement(value)
            let usagePage = IOHIDElementGetUsagePage(element)
            let usage = IOHIDElementGetUsage(element)
            let cookie = UInt32(IOHIDElementGetCookie(element))
            let integerValue = IOHIDValueGetIntegerValue(value)
            let bytes = byteArray(from: IOHIDValueGetBytePtr(value), length: max(0, Int(IOHIDValueGetLength(value))))
            let timestamp = dateFormatter.string(from: Date())

            if shouldSuppressValue(
                eventFilter: registration.eventFilter,
                descriptor: registration.descriptor,
                usagePage: Int(usagePage),
                usage: Int(usage)
            ) {
                continue
            }

            print(
                "[value] \(timestamp)  " +
                String(format: "page=0x%02X usage=0x%02X cookie=0x%08X value=%lld", usagePage, usage, cookie, integerValue) +
                (bytes.isEmpty ? "" : " bytes=\(hexString(from: bytes))")
            )
        }
    }

    private func pollFeatureReports(for registration: Registration) {
        for reportID in registration.reportIDs {
            var reportLength = registration.reportBufferLength
            registration.featureReportBuffer.initialize(repeating: 0, count: Int(registration.reportBufferLength))
            let status = IOHIDDeviceGetReport(
                registration.descriptor.device,
                kIOHIDReportTypeFeature,
                CFIndex(reportID),
                registration.featureReportBuffer,
                &reportLength
            )
            guard status == kIOReturnSuccess else {
                continue
            }

            let bytes = byteArray(from: registration.featureReportBuffer, length: Int(reportLength))
            if registration.lastFeatureReports[reportID] != bytes {
                registration.lastFeatureReports[reportID] = bytes
                let timestamp = dateFormatter.string(from: Date())

                print(
                    "[report] \(timestamp)  type=feature id=\(reportID) len=\(reportLength)" +
                    (bytes.isEmpty ? "" : " bytes=\(hexString(from: bytes))")
                )
            }
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
        guard result == kIOReturnSuccess, let context = context else {
            return
        }

        let registration = Unmanaged<Registration>.fromOpaque(context).takeUnretainedValue()
        let timestamp = registration.dateFormatter.string(from: Date())
        let bytes = byteArray(from: report, length: Int(reportLength))
        if shouldSuppressInputReport(registration: registration, bytes: bytes) {
            return
        }

        print(
            "[input-report] \(timestamp)  type=\(reportTypeName(type)) id=\(reportID) len=\(reportLength)" +
            (bytes.isEmpty ? "" : " bytes=\(hexString(from: bytes))")
        )
    }
}

private func probeDeviceGroupSort(_ groups: [String: [HIDDeviceDescriptor]]) -> (String, String) -> Bool {
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

private func inputElements(on device: IOHIDDevice) -> [IOHIDElement] {
    guard let values = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [Any] else {
        return []
    }

    return values.compactMap { value in
        let element = value as! IOHIDElement
        switch IOHIDElementGetType(element) {
        case kIOHIDElementTypeInput_Misc, kIOHIDElementTypeInput_Button, kIOHIDElementTypeInput_Axis, kIOHIDElementTypeInput_ScanCodes:
            return element
        default:
            return nil
        }
    }
}

private func shouldSuppressValue(
    eventFilter: HIDInterfaceProbe.EventFilter,
    descriptor: HIDDeviceDescriptor,
    usagePage: Int,
    usage: Int
) -> Bool {
    guard (eventFilter == .deathAdderV2SpecialOnly || eventFilter == .deathAdderV2Audit),
          descriptor.elementSummary.role == "mouse+vendor"
    else {
        return false
    }

    if usagePage == 0x01 && (usage == 0x30 || usage == 0x31 || usage == 0x38) {
        return true
    }

    if usagePage == 0x09 && (usage == 0x01 || usage == 0x02) {
        return true
    }

    if eventFilter == .deathAdderV2SpecialOnly && usagePage >= 0xFF00 {
        return true
    }

    return false
}

private func shouldSuppressInputReport(
    registration: HIDInterfaceProbe.Registration,
    bytes: [UInt8]
) -> Bool {
    guard (registration.eventFilter == .deathAdderV2SpecialOnly || registration.eventFilter == .deathAdderV2Audit),
          registration.descriptor.elementSummary.role == "mouse+vendor",
          let buttonMask = bytes.first
    else {
        return false
    }

    if registration.eventFilter == .deathAdderV2Audit {
        let signature = mouseAuditSignature(from: bytes)
        let previousSignature = registration.lastMouseAuditSignature
        registration.lastMouseAuditSignature = signature

        return signature == previousSignature
    }

    let specialButtonMask = buttonMask & ~0x03
    let previousSpecialButtonMask = registration.lastSpecialMouseButtonMask
    registration.lastSpecialMouseButtonMask = specialButtonMask

    return specialButtonMask == previousSpecialButtonMask
}

private func mouseAuditSignature(from bytes: [UInt8]) -> [UInt8] {
    guard let buttonMask = bytes.first else {
        return []
    }

    var signature = [buttonMask & ~0x03]
    if bytes.count >= 3 {
        signature.append(bytes[1])
        signature.append(bytes[2])
    }
    return signature
}

private func byteArray(from pointer: UnsafePointer<UInt8>?, length: Int) -> [UInt8] {
    guard let pointer = pointer, length > 0 else {
        return []
    }
    return Array(UnsafeBufferPointer(start: pointer, count: length))
}

private func byteArray(from pointer: UnsafeMutablePointer<UInt8>, length: Int) -> [UInt8] {
    if length <= 0 {
        return []
    }
    return Array(UnsafeBufferPointer(start: UnsafePointer(pointer), count: length))
}

private func hexString(from bytes: [UInt8]) -> String {
    if bytes.isEmpty {
        return ""
    }
    return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

private func reportTypeName(_ type: IOHIDReportType) -> String {
    switch type {
    case kIOHIDReportTypeInput:
        return "input"
    case kIOHIDReportTypeOutput:
        return "output"
    case kIOHIDReportTypeFeature:
        return "feature"
    default:
        return "unknown"
    }
}
