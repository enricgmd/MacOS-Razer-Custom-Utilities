import Dispatch
import Foundation
import IOKit
import IOUSBHost

enum USBHostProbeError: Error, CustomStringConvertible {
    case missingVendorOrProduct
    case noMatchingInterface(Int)
    case serviceMatchFailed(IOReturn)
    case interfaceOpenFailed(String)
    case pipeOpenFailed(Int, String)
    case requestFailed(String)

    var description: String {
        switch self {
        case .missingVendorOrProduct:
            return "USBHost probing requires both --vendor-id and --product-id."
        case .noMatchingInterface(let number):
            return "No IOUSBHostInterface matched USB interface number \(number)."
        case .serviceMatchFailed(let status):
            return String(format: "IOService matching failed (0x%08X).", status)
        case .interfaceOpenFailed(let message):
            return "Unable to open IOUSBHostInterface: \(message)"
        case .pipeOpenFailed(let endpoint, let message):
            return String(format: "Unable to open endpoint 0x%02X: %@", endpoint, message)
        case .requestFailed(let message):
            return "USB request failed: \(message)"
        }
    }
}

final class USBHostProbe {
    private let options: CLIOptions
    private let endpointAddress: Int
    private let dateFormatter: DateFormatter
    private var previousSpecialCodes = Set<UInt8>()

    init(options: CLIOptions) throws {
        self.options = options
        self.endpointAddress = options.endpointAddress ?? 0x82
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }

    func start() throws {
        guard let vendorID = options.vendorID, let productID = options.productID else {
            throw USBHostProbeError.missingVendorOrProduct
        }
        guard let usbInterfaceNumber = options.usbInterfaceNumber else {
            throw USBHostProbeError.noMatchingInterface(-1)
        }

        let service = try matchingInterfaceService(vendorID: vendorID, productID: productID, interfaceNumber: usbInterfaceNumber)
        defer { IOObjectRelease(service) }

        print("Matched IOUSBHostInterface:")
        print("  \(serviceSummary(service))")

        let queue = DispatchQueue(label: "razer-hid-tool.usbhost")
        var initOptions: IOUSBHostObjectInitOptions = []
        if options.usbHostCapture {
            initOptions.insert(.deviceCapture)
        }
        if options.usbHostSeize {
            initOptions.insert(.deviceSeize)
        }
        let hostInterface: IOUSBHostInterface
        do {
            hostInterface = try IOUSBHostInterface(
                __ioService: service,
                options: initOptions,
                queue: queue,
                interestHandler: { _, messageType, _ in
                    print(String(format: "[usbhost] interest message=0x%08X", messageType))
                }
            )
        } catch {
            throw USBHostProbeError.interfaceOpenFailed(errorDescription(error))
        }
        defer { hostInterface.destroy() }

        let descriptor = hostInterface.interfaceDescriptor.pointee
        print(
            String(
                format: "Opened USB interface number=%d class=0x%02X subclass=0x%02X protocol=0x%02X endpoints=%d options=%@",
                descriptor.bInterfaceNumber,
                descriptor.bInterfaceClass,
                descriptor.bInterfaceSubClass,
                descriptor.bInterfaceProtocol,
                descriptor.bNumEndpoints,
                initOptionsDescription(initOptions)
            )
        )

        let pipe: IOUSBHostPipe
        do {
            pipe = try hostInterface.copyPipe(withAddress: endpointAddress)
        } catch {
            throw USBHostProbeError.pipeOpenFailed(endpointAddress, errorDescription(error))
        }

        print(String(format: "Listening on USB endpoint 0x%02X. Press Ctrl-C to stop.", endpointAddress))

        while true {
            try readOneInterruptPacket(from: pipe)
        }
    }

    private func matchingInterfaceService(vendorID: Int, productID: Int, interfaceNumber: Int) throws -> io_service_t {
        guard let dictionary = IOServiceMatching("IOUSBHostInterface") else {
            throw USBHostProbeError.noMatchingInterface(interfaceNumber)
        }

        var iterator: io_iterator_t = 0
        let mainPort: mach_port_t
        if #available(macOS 12.0, *) {
            mainPort = kIOMainPortDefault
        } else {
            mainPort = kIOMasterPortDefault
        }
        let status = IOServiceGetMatchingServices(mainPort, dictionary, &iterator)
        guard status == kIOReturnSuccess else {
            throw USBHostProbeError.serviceMatchFailed(status)
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else {
                break
            }

            let currentVendorID = propertyInt(service, "idVendor") ?? -1
            let currentProductID = propertyInt(service, "idProduct") ?? -1
            let currentInterfaceNumber = propertyInt(service, "bInterfaceNumber") ?? -1
            if currentVendorID == vendorID && currentProductID == productID && currentInterfaceNumber == interfaceNumber {
                return service
            }

            IOObjectRelease(service)
        }

        throw USBHostProbeError.noMatchingInterface(interfaceNumber)
    }

    private func readOneInterruptPacket(from pipe: IOUSBHostPipe) throws {
        guard let data = NSMutableData(length: 64) else {
            throw USBHostProbeError.requestFailed("Unable to allocate transfer buffer.")
        }

        let semaphore = DispatchSemaphore(value: 0)
        var completionStatus: IOReturn = kIOReturnError
        var transferredByteCount = 0

        do {
            try pipe.enqueueIORequest(with: data, completionTimeout: 0) { status, bytesTransferred in
                completionStatus = status
                transferredByteCount = bytesTransferred
                semaphore.signal()
            }
        } catch {
            throw USBHostProbeError.requestFailed(error.localizedDescription)
        }

        semaphore.wait()

        guard completionStatus == kIOReturnSuccess else {
            print(String(format: "[usbhost] request status=0x%08X transferred=%d", completionStatus, transferredByteCount))
            return
        }

        let bytes = byteArray(from: data.bytes.assumingMemoryBound(to: UInt8.self), length: transferredByteCount)
        printDecodedPacket(bytes)
    }

    private func printDecodedPacket(_ bytes: [UInt8]) {
        let timestamp = dateFormatter.string(from: Date())
        let decoded = decodeRazerSpecialReport(bytes)
        print(
            "[usbhost] \(timestamp)  len=\(bytes.count)" +
            (bytes.isEmpty ? "" : " bytes=\(hexString(from: bytes))") +
            (decoded.isEmpty ? "" : " decoded=\(decoded)")
        )
    }

    private func decodeRazerSpecialReport(_ bytes: [UInt8]) -> String {
        guard bytes.first == 0x04 else {
            return ""
        }

        let currentCodes = Set(bytes.dropFirst().filter { $0 != 0 })
        let pressed = currentCodes.subtracting(previousSpecialCodes).sorted()
        let released = previousSpecialCodes.subtracting(currentCodes).sorted()
        previousSpecialCodes = currentCodes

        var parts: [String] = []
        for code in pressed {
            parts.append("\(specialCodeName(code)):down")
        }
        for code in released {
            parts.append("\(specialCodeName(code)):up")
        }
        return parts.joined(separator: ",")
    }

    private func serviceSummary(_ service: io_service_t) -> String {
        let product = propertyString(service, "USB Product Name") ?? "unknown"
        let location = propertyInt(service, "locationID") ?? 0
        let interfaceNumber = propertyInt(service, "bInterfaceNumber") ?? -1
        let interfaceClass = propertyInt(service, "bInterfaceClass") ?? -1
        let interfaceSubclass = propertyInt(service, "bInterfaceSubClass") ?? -1
        let interfaceProtocol = propertyInt(service, "bInterfaceProtocol") ?? -1
        let endpoints = propertyInt(service, "bNumEndpoints") ?? -1
        let owner = propertyString(service, "UsbExclusiveOwner") ?? "none"

        return String(
            format: "%@ location=0x%08X interface=%d class=0x%02X subclass=0x%02X protocol=0x%02X endpoints=%d owner=%@",
            product,
            location,
            interfaceNumber,
            interfaceClass,
            interfaceSubclass,
            interfaceProtocol,
            endpoints,
            owner
        )
    }
}

private func propertyInt(_ service: io_service_t, _ key: String) -> Int? {
    guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
        return nil
    }
    return value as? Int
}

private func propertyString(_ service: io_service_t, _ key: String) -> String? {
    guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
        return nil
    }
    return value as? String
}

private func errorDescription(_ error: Error) -> String {
    let nsError = error as NSError
    return "\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)"
}

private func initOptionsDescription(_ options: IOUSBHostObjectInitOptions) -> String {
    var parts: [String] = []
    if options.contains(.deviceCapture) {
        parts.append("capture")
    }
    if options.contains(.deviceSeize) {
        parts.append("seize")
    }
    return parts.isEmpty ? "none" : parts.joined(separator: "+")
}

private func specialCodeName(_ code: UInt8) -> String {
    switch code {
    case 0x01: return "FN"
    case 0x20: return "M1/F13"
    case 0x21: return "M2/F14"
    case 0x22: return "M3/F15"
    case 0x23: return "M4/F16"
    case 0x24: return "M5/F17"
    case 0x25: return "M6/F18"
    case 0x50: return "VolumeDown"
    case 0x51: return "VolumeUp"
    case 0x52: return "Mute"
    case 0x53: return "Next"
    case 0x54: return "Previous"
    case 0x55: return "PlayPause"
    default: return String(format: "0x%02X", code)
    }
}

private func byteArray(from pointer: UnsafePointer<UInt8>?, length: Int) -> [UInt8] {
    guard let pointer = pointer, length > 0 else {
        return []
    }
    return Array(UnsafeBufferPointer(start: pointer, count: length))
}

private func hexString(from bytes: [UInt8]) -> String {
    if bytes.isEmpty {
        return ""
    }
    return bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}
