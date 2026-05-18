import Foundation
import IOKit.hidsystem
import ApplicationServices

enum HIDPermissionState {
    case granted
    case denied
    case unknown

    var label: String {
        switch self {
        case .granted:
            return "Input Monitoring granted"
        case .denied:
            return "Input Monitoring denied"
        case .unknown:
            return "Input Monitoring permission required"
        }
    }
}

enum HIDPermissionService {
    static func checkListenAccess() -> HIDPermissionState {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .unknown
        }
    }

    @discardableResult
    static func requestListenAccess() -> HIDPermissionState {
        if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            return .granted
        }
        return checkListenAccess()
    }
}

enum AccessibilityPermissionService {
    static func checkAccess() -> HIDPermissionState {
        AXIsProcessTrusted() ? .granted : .unknown
    }

    @discardableResult
    static func requestAccess() -> HIDPermissionState {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        if AXIsProcessTrustedWithOptions(options) {
            return .granted
        }

        return checkAccess()
    }
}
