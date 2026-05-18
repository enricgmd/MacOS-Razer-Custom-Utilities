import AppKit
import Darwin
import Foundation
import IOKit.hid

final class CapsLockLEDController {
    private let vendorID = 0x1532
    private let productID = 0x0293
    private let ledUsagePage = 0x08
    private let capsLockLEDUsage = 0x02

    private var manager: IOHIDManager?
    private var targets: [LEDTarget] = []
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var refreshTimer: Timer?
    private var lastState: Bool?
    private var isStarted = false

    func start() {
        guard !isStarted else {
            updateLED(force: true)
            return
        }

        stop()
        isStarted = true
        attachTargets()
        updateLED(force: true)
        startEventTap()

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateLED(force: true)
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }

        eventTapSource = nil
        eventTap = nil
        targets.removeAll()

        if let manager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        lastState = nil
        isStarted = false
    }

    private func attachTargets() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let devices = IOHIDManagerCopyDevices(manager) as NSSet? else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            return
        }

        for value in devices {
            let device = value as! IOHIDDevice
            guard intProperty(kIOHIDVendorIDKey as CFString, on: device) == vendorID,
                  intProperty(kIOHIDProductIDKey as CFString, on: device) == productID,
                  let element = capsLockLEDOutputElement(on: device)
            else {
                continue
            }

            let status = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard status == kIOReturnSuccess else {
                continue
            }

            targets.append(LEDTarget(device: device, element: element))
        }

        if targets.isEmpty {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        } else {
            self.manager = manager
        }
    }

    private func capsLockLEDOutputElement(on device: IOHIDDevice) -> IOHIDElement? {
        let matching: [String: Any] = [
            kIOHIDElementUsagePageKey: ledUsagePage,
            kIOHIDElementUsageKey: capsLockLEDUsage
        ]

        guard let elements = IOHIDDeviceCopyMatchingElements(
            device,
            matching as CFDictionary,
            IOOptionBits(kIOHIDOptionsTypeNone)
        ) as? [IOHIDElement]
        else {
            return nil
        }

        return elements.first { IOHIDElementGetType($0) == kIOHIDElementTypeOutput }
    }

    private func startEventTap() {
        let events = 1 << CGEventType.flagsChanged.rawValue
        let context = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(events),
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let controller = Unmanaged<CapsLockLEDController>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = controller.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                controller.updateLED(force: false)
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        )

        guard let eventTap else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func updateLED(force: Bool) {
        guard !targets.isEmpty else {
            return
        }

        let state = CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift)
        guard force || state != lastState else {
            return
        }
        lastState = state

        for target in targets {
            let minValue = IOHIDElementGetLogicalMin(target.element)
            let maxValue = IOHIDElementGetLogicalMax(target.element)
            let integerValue = state ? max(maxValue, 1) : minValue

            let hidValue = IOHIDValueCreateWithIntegerValue(
                kCFAllocatorDefault,
                target.element,
                mach_absolute_time(),
                integerValue
            )

            IOHIDDeviceSetValue(target.device, target.element, hidValue)
        }
    }
}

private struct LEDTarget {
    let device: IOHIDDevice
    let element: IOHIDElement
}

private func intProperty(_ key: CFString, on device: IOHIDDevice) -> Int {
    guard let value = IOHIDDeviceGetProperty(device, key) as? NSNumber else {
        return 0
    }
    return value.intValue
}
