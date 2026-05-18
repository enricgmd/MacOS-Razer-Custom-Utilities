import Foundation
import Darwin

setbuf(stdout, nil)

do {
    let options = try CLIOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))

    switch options.mode {
    case .list:
        let lister = try HIDDeviceLister(options: options)
        let lines = lister.renderList()
        if lines.isEmpty {
            print("No matching HID devices found.")
        } else {
            lines.forEach { print($0) }
        }
    case .probe:
        let probe = try HIDInterfaceProbe(options: options)
        try probe.start()
    case .probeAll:
        let probe = try HIDInterfaceProbe(options: options)
        try probe.startAllInterfaces()
    case .dump:
        let dumper = try HIDReportDescriptorDumper(options: options)
        try dumper.dump()
    case .usbhostProbe:
        let probe = try USBHostProbe(options: options)
        try probe.start()
    case .razerMacroOn:
        let controller = try RazerMacroController(options: options)
        try controller.enable()
    case .razerMacroOff:
        let controller = try RazerMacroController(options: options)
        try controller.disable()
    case .razerMacroListen:
        let listener = try RazerMacroListener(options: options)
        try listener.start()
    case .deathAdderV2Listen:
        let probe = try HIDInterfaceProbe(options: options)
        try probe.startAllInterfaces(eventFilter: .deathAdderV2SpecialOnly)
    case .deathAdderV2Audit:
        let probe = try HIDInterfaceProbe(options: options)
        try probe.startAllInterfaces(eventFilter: .deathAdderV2Audit)
    case .deathAdderV2MacroListen:
        let listener = try DeathAdderMacroListener(options: options)
        try listener.start()
    case .deathAdderV2FKeyListen:
        let listener = DeathAdderFKeyListener()
        try listener.start()
    case .deathAdderV2FKeyDebug:
        let listener = DeathAdderFKeyListener(debugUnmatchedEvents: true)
        try listener.start()
    case .deathAdderV2ButtonsListen:
        let listener = DeathAdderButtonListener()
        try listener.start()
    case .listen:
        let monitor = KeyboardEventMonitor()
        try monitor.start()
    }
} catch let error as CLIError {
    fputs("\(error.description)\n", stderr)
    switch error {
    case .help:
        exit(0)
    default:
        exit(1)
    }
} catch let error as CustomStringConvertible {
    fputs("\(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("Unexpected error: \(error)\n", stderr)
    exit(1)
}
