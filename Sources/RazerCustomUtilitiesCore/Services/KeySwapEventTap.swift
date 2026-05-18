import AppKit

final class KeySwapEventTap {
    private let syntheticMarker: Int64 = 0x52435F53574150
    private var rulesBySource: [UInt16: KeySwapRule] = [:]
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var activeSources: [UInt16: KeyDescriptor] = [:]

    func updateRules(_ rules: [KeySwapRule]) {
        let allowedRules = rules.filter {
            KeyDescriptor.isAllowedForKeySwapper($0.source.keyCode)
                && KeyDescriptor.isAllowedForKeySwapper($0.destination.keyCode)
        }
        rulesBySource = Dictionary(uniqueKeysWithValues: allowedRules.map { ($0.source.keyCode, $0) })

        if rulesBySource.isEmpty {
            stop()
        } else {
            start()
        }
    }

    func stop() {
        releaseActiveDestinations()

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }

        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }

        eventTapSource = nil
        eventTap = nil
    }

    private func start() {
        guard eventTap == nil else {
            return
        }

        let events = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(events),
            callback: { _, type, event, userInfo in
                guard let userInfo else {
                    return Unmanaged.passUnretained(event)
                }

                let service = Unmanaged<KeySwapEventTap>
                    .fromOpaque(userInfo)
                    .takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let eventTap = service.eventTap {
                        CGEvent.tapEnable(tap: eventTap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                return service.handle(type: type, event: event)
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

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard KeyDescriptor.isAllowedForKeySwapper(keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            guard let rule = rulesBySource[keyCode],
                  !rule.source.isModifier,
                  sourceMatches(rule.source, eventFlags: event.flags)
            else {
                return Unmanaged.passUnretained(event)
            }
            activeSources[keyCode] = rule.destination
            post(destination: rule.destination, keyDown: true, sourceFlags: event.flags)
            return nil

        case .keyUp:
            guard let destination = activeSources.removeValue(forKey: keyCode) else {
                return Unmanaged.passUnretained(event)
            }
            post(destination: destination, keyDown: false, sourceFlags: event.flags)
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func post(
        destination: KeyDescriptor,
        keyDown: Bool,
        sourceFlags: CGEventFlags
    ) {
        let destinationFlags = destination.cgEventFlags
        let flags: CGEventFlags
        if destinationFlags.isEmpty {
            flags = sourceFlags
        } else {
            flags = destinationFlags
        }
        postKeyEvent(keyCode: destination.keyCode, keyDown: keyDown, flags: flags)
    }

    private func sourceMatches(_ source: KeyDescriptor, eventFlags: CGEventFlags) -> Bool {
        let requiredFlags = source.cgEventFlags
        guard !requiredFlags.isEmpty else {
            return true
        }

        return printableFlags(from: eventFlags) == requiredFlags
    }

    private func printableFlags(from flags: CGEventFlags) -> CGEventFlags {
        var printableFlags = CGEventFlags()

        if flags.contains(.maskAlternate) {
            printableFlags.insert(.maskAlternate)
        }
        if flags.contains(.maskShift) {
            printableFlags.insert(.maskShift)
        }

        return printableFlags
    }

    private func postKeyEvent(keyCode: UInt16, keyDown: Bool, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        source.userData = syntheticMarker
        let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(keyCode),
            keyDown: keyDown
        )
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private func releaseActiveDestinations() {
        for destination in activeSources.values {
            post(destination: destination, keyDown: false, sourceFlags: [])
        }
        activeSources.removeAll()
    }
}
