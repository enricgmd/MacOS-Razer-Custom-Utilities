import AppKit
import Foundation

final class DeathAdderFKeySuppressor {
    private struct PendingEvent {
        let isDown: Bool
        let createdAt: CFAbsoluteTime
    }

    private static let keyCodesByKeyboardUsage: [UInt32: UInt16] = [
        0x6A: 113,
        0x6B: 106
    ]

    private let suppressionWindow: CFTimeInterval = 0.25
    private let lock = NSLock()
    private var pendingEventsByKeyCode: [UInt16: [PendingEvent]] = [:]
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    func start() {
        guard eventTap == nil else {
            return
        }

        let events = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(events),
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let suppressor = Unmanaged<DeathAdderFKeySuppressor>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = suppressor.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                return suppressor.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            NSLog("Unable to create DeathAdder F-key suppressor event tap.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }

        lock.lock()
        pendingEventsByKeyCode.removeAll()
        lock.unlock()

        eventTapSource = nil
        eventTap = nil
    }

    func noteDeathAdderKeyboardUsage(_ usage: UInt32, value: Int) {
        guard let keyCode = Self.keyCodesByKeyboardUsage[usage],
              value == 0 || value == 1 else {
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        let pendingEvent = PendingEvent(isDown: value == 1, createdAt: now)

        lock.lock()
        pruneExpiredEvents(now: now)
        pendingEventsByKeyCode[keyCode, default: []].append(pendingEvent)
        lock.unlock()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isDown: Bool

        switch type {
        case .keyDown:
            isDown = true
        case .keyUp:
            isDown = false
        default:
            return Unmanaged.passUnretained(event)
        }

        guard consumePendingEvent(keyCode: keyCode, isDown: isDown) else {
            return Unmanaged.passUnretained(event)
        }

        return nil
    }

    private func consumePendingEvent(keyCode: UInt16, isDown: Bool) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()

        lock.lock()
        defer { lock.unlock() }

        pruneExpiredEvents(now: now)

        guard var pendingEvents = pendingEventsByKeyCode[keyCode],
              let index = pendingEvents.firstIndex(where: { $0.isDown == isDown }) else {
            return false
        }

        pendingEvents.remove(at: index)
        if pendingEvents.isEmpty {
            pendingEventsByKeyCode.removeValue(forKey: keyCode)
        } else {
            pendingEventsByKeyCode[keyCode] = pendingEvents
        }

        return true
    }

    private func pruneExpiredEvents(now: CFAbsoluteTime) {
        pendingEventsByKeyCode = pendingEventsByKeyCode.compactMapValues { pendingEvents in
            let freshEvents = pendingEvents.filter {
                now - $0.createdAt <= suppressionWindow
            }
            return freshEvents.isEmpty ? nil : freshEvents
        }
    }
}
