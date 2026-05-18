import Foundation
import IOKit.hid

enum RazerHIDServiceError: LocalizedError {
    case helperUnavailable
    case helperFailed(String)
    case inputInterfaceUnavailable

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            return "razer-hid-tool helper not found inside the app bundle."
        case .helperFailed(let message):
            return message.isEmpty ? "razer-hid-tool helper failed." : message
        case .inputInterfaceUnavailable:
            return "Razer macro input interface is unavailable."
        }
    }
}

final class RazerHIDService {
    var onMacroEvent: ((MacroKeyEvent) -> Void)?

    private let vendorID = 0x1532
    private let productID = 0x0293
    private var inputManager: IOHIDManager?
    private var registrations: [InputRegistration] = []
    private var activeCodes = Set<UInt8>()

    deinit {
        stopListening()
    }

    func startListening() throws {
        stopListening()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        let devices = matchingDevices(using: manager)
            .filter { maxReportSize(kIOHIDMaxInputReportSizeKey as CFString, on: $0) >= 22 }

        for device in devices {
            let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard status == kIOReturnSuccess else {
                continue
            }

            let registration = InputRegistration(device: device, reportLength: maxReportSize(kIOHIDMaxInputReportSizeKey as CFString, on: device))
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceRegisterInputReportCallback(
                device,
                registration.buffer,
                registration.bufferLength,
                { context, result, sender, type, reportID, report, reportLength in
                    guard let context = context else {
                        return
                    }
                    let service = Unmanaged<RazerHIDService>.fromOpaque(context).takeUnretainedValue()
                    service.handleInputReport(result: result, type: type, reportID: reportID, report: report, reportLength: reportLength)
                },
                Unmanaged.passUnretained(self).toOpaque()
            )
            registrations.append(registration)
        }

        guard !registrations.isEmpty else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw RazerHIDServiceError.inputInterfaceUnavailable
        }

        inputManager = manager
    }

    func stopListening() {
        registrations.removeAll()
        if let inputManager {
            IOHIDManagerClose(inputManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        inputManager = nil
        activeCodes.removeAll()
    }

    func setMacroModeEnabled(_ enabled: Bool) throws {
        if enabled {
            try runHelper(arguments: [
                "--razer-macro-on",
                "--vendor-id", "0x1532",
                "--product-id", "0x0293"
            ])
            try startListening()
        } else {
            stopListening()
            try runHelper(arguments: [
                "--razer-macro-off",
                "--vendor-id", "0x1532",
                "--product-id", "0x0293"
            ])
        }
    }

    func isDeviceConnected() -> Bool {
        do {
            let output = try runHelper(arguments: [
                "--list",
                "--vendor-id", "0x1532",
                "--product-id", "0x0293"
            ])
            return output.contains("Razer BlackWidow V4 X")
        } catch {
            return false
        }
    }

    private func makeHelperProcess(arguments: [String]) throws -> Process {
        let helperURL = try helperExecutableURL()
        let process = Process()
        process.executableURL = helperURL
        process.arguments = arguments
        return process
    }

    @discardableResult
    private func runHelper(arguments: [String]) throws -> String {
        let process = try makeHelperProcess(arguments: arguments)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw RazerHIDServiceError.helperFailed(output)
        }

        return output
    }

    private func helperExecutableURL() throws -> URL {
        let bundleHelper = Bundle.main.resourceURL?
            .appendingPathComponent("bin")
            .appendingPathComponent("razer-hid-tool")
        if let bundleHelper, FileManager.default.isExecutableFile(atPath: bundleHelper.path) {
            return bundleHelper
        }

        throw RazerHIDServiceError.helperUnavailable
    }

    private func matchingDevices(using manager: IOHIDManager) -> [IOHIDDevice] {
        guard let values = IOHIDManagerCopyDevices(manager) as NSSet? else {
            return []
        }

        return values.compactMap { value in
            let device = value as! IOHIDDevice
            guard intProperty(kIOHIDVendorIDKey as CFString, on: device) == vendorID,
                  intProperty(kIOHIDProductIDKey as CFString, on: device) == productID
            else {
                return nil
            }
            return device
        }
    }

    private func handleInputReport(
        result: IOReturn,
        type: IOHIDReportType,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>?,
        reportLength: CFIndex
    ) {
        guard result == kIOReturnSuccess,
              type == kIOHIDReportTypeInput,
              reportID == 4,
              let report = report,
              reportLength >= 2
        else {
            return
        }

        let bytes = Array(UnsafeBufferPointer(start: UnsafePointer(report), count: Int(reportLength)))
        guard bytes.first == 0x04 else {
            return
        }

        let code = bytes[1]
        if (0x20...0x25).contains(code) {
            if activeCodes.insert(code).inserted {
                onMacroEvent?(.down(code))
            }
        } else if code == 0x00 {
            let releasedCodes = activeCodes
            activeCodes.removeAll()
            for releasedCode in releasedCodes {
                onMacroEvent?(.up(releasedCode))
            }
        }
    }
}

private final class InputRegistration {
    let device: IOHIDDevice
    let buffer: UnsafeMutablePointer<UInt8>
    let bufferLength: CFIndex

    init(device: IOHIDDevice, reportLength: Int) {
        self.device = device
        self.bufferLength = CFIndex(max(1, reportLength))
        self.buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(bufferLength))
        self.buffer.initialize(repeating: 0, count: Int(bufferLength))
    }

    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        buffer.deinitialize(count: Int(bufferLength))
        buffer.deallocate()
    }
}

private func intProperty(_ key: CFString, on device: IOHIDDevice) -> Int {
    guard let value = IOHIDDeviceGetProperty(device, key) as? NSNumber else {
        return 0
    }
    return value.intValue
}

private func maxReportSize(_ key: CFString, on device: IOHIDDevice) -> Int {
    max(0, intProperty(key, on: device))
}
