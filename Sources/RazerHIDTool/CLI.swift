import Foundation

struct CLIOptions {
    enum Mode {
        case list
        case listen
        case probe
        case probeAll
        case dump
        case usbhostProbe
        case razerMacroOn
        case razerMacroOff
        case razerMacroListen
        case deathAdderV2Listen
        case deathAdderV2Audit
        case deathAdderV2MacroListen
        case deathAdderV2FKeyListen
        case deathAdderV2FKeyDebug
        case deathAdderV2ButtonsListen
    }

    let mode: Mode
    let vendorID: Int?
    let productID: Int?
    let keyboardOnly: Bool
    let interfaceIndex: Int?
    let usbInterfaceNumber: Int?
    let endpointAddress: Int?
    let usbHostCapture: Bool
    let usbHostSeize: Bool

    static func parse(arguments: [String]) throws -> CLIOptions {
        var mode: Mode = .listen
        var vendorID: Int?
        var productID: Int?
        var keyboardOnly = false
        var interfaceIndex: Int?
        var usbInterfaceNumber: Int?
        var endpointAddress: Int?
        var usbHostCapture = false
        var usbHostSeize = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]

            switch argument {
            case "--help", "-h":
                throw CLIError.help
            case "--list":
                mode = .list
            case "--listen":
                mode = .listen
            case "--probe-interface":
                mode = .probe
                index += 1
                interfaceIndex = try parseIntegerArgument(named: "--probe-interface", at: index, in: arguments)
            case "--probe-all-interfaces":
                mode = .probeAll
            case "--dump-interface":
                mode = .dump
                index += 1
                interfaceIndex = try parseIntegerArgument(named: "--dump-interface", at: index, in: arguments)
            case "--usbhost-probe":
                mode = .usbhostProbe
                index += 1
                usbInterfaceNumber = try parseIntegerArgument(named: "--usbhost-probe", at: index, in: arguments)
            case "--endpoint":
                index += 1
                endpointAddress = try parseIntegerArgument(named: "--endpoint", at: index, in: arguments)
            case "--usbhost-capture":
                usbHostCapture = true
            case "--usbhost-seize":
                usbHostSeize = true
            case "--razer-macro-on":
                mode = .razerMacroOn
            case "--razer-macro-off":
                mode = .razerMacroOff
            case "--razer-macro-listen":
                mode = .razerMacroListen
            case "--deathadder-v2-listen":
                mode = .deathAdderV2Listen
                if vendorID == nil {
                    vendorID = 0x1532
                }
                if productID == nil {
                    productID = 0x0084
                }
            case "--deathadder-v2-audit":
                mode = .deathAdderV2Audit
                if vendorID == nil {
                    vendorID = 0x1532
                }
                if productID == nil {
                    productID = 0x0084
                }
            case "--deathadder-v2-macro-listen":
                mode = .deathAdderV2MacroListen
                if vendorID == nil {
                    vendorID = 0x1532
                }
                if productID == nil {
                    productID = 0x0084
                }
            case "--deathadder-v2-fkey-listen":
                mode = .deathAdderV2FKeyListen
            case "--deathadder-v2-fkey-debug":
                mode = .deathAdderV2FKeyDebug
            case "--deathadder-v2-buttons-listen":
                mode = .deathAdderV2ButtonsListen
            case "--vendor-id":
                index += 1
                vendorID = try parseIntegerArgument(named: "--vendor-id", at: index, in: arguments)
            case "--product-id":
                index += 1
                productID = try parseIntegerArgument(named: "--product-id", at: index, in: arguments)
            case "--keyboard-only":
                keyboardOnly = true
            case "--all-devices":
                keyboardOnly = false
            default:
                throw CLIError.unknownArgument(argument)
            }

            index += 1
        }

        if (mode == .probe || mode == .dump) && interfaceIndex == nil {
            throw CLIError.invalidConfiguration("The selected mode requires an interface number.")
        }

        if mode == .usbhostProbe && usbInterfaceNumber == nil {
            throw CLIError.invalidConfiguration("The selected mode requires a USB interface number.")
        }

        if (mode == .probe || mode == .probeAll || mode == .dump || mode == .usbhostProbe || mode == .razerMacroOn || mode == .razerMacroOff || mode == .razerMacroListen || mode == .deathAdderV2Listen || mode == .deathAdderV2Audit || mode == .deathAdderV2MacroListen) && (vendorID == nil || productID == nil) {
            throw CLIError.invalidConfiguration("The selected mode requires both --vendor-id and --product-id.")
        }

        return CLIOptions(
            mode: mode,
            vendorID: vendorID,
            productID: productID,
            keyboardOnly: keyboardOnly,
            interfaceIndex: interfaceIndex,
            usbInterfaceNumber: usbInterfaceNumber,
            endpointAddress: endpointAddress,
            usbHostCapture: usbHostCapture,
            usbHostSeize: usbHostSeize
        )
    }

    static var helpText: String {
        """
        razer-hid-tool

        Explora dispositivos HID USB en macOS y captura eventos/raw reports.

        Uso:
          razer-hid-tool
          razer-hid-tool --list [--vendor-id 0x1532] [--product-id 0x0293] [--keyboard-only]
          razer-hid-tool --listen
          razer-hid-tool --probe-interface 3 --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --probe-all-interfaces --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --dump-interface 3 --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --usbhost-probe 3 --endpoint 0x82 --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --razer-macro-on --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --razer-macro-off --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --razer-macro-listen --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --deathadder-v2-listen
          razer-hid-tool --deathadder-v2-audit
          razer-hid-tool --deathadder-v2-fkey-listen
          razer-hid-tool --deathadder-v2-fkey-debug
          razer-hid-tool --deathadder-v2-buttons-listen

        Ejemplos:
          razer-hid-tool
          razer-hid-tool --list
          razer-hid-tool --list --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --listen
          razer-hid-tool --probe-interface 3 --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --probe-all-interfaces --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --dump-interface 3 --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --usbhost-probe 3 --endpoint 0x82 --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --razer-macro-on --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --razer-macro-off --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --razer-macro-listen --vendor-id 0x1532 --product-id 0x0293
          razer-hid-tool --deathadder-v2-listen
          razer-hid-tool --deathadder-v2-audit
          razer-hid-tool --deathadder-v2-listen --vendor-id 0x1532 --product-id 0x0084
          razer-hid-tool --deathadder-v2-fkey-listen
          razer-hid-tool --deathadder-v2-fkey-debug
          razer-hid-tool --deathadder-v2-buttons-listen

        Notas:
          - Sin argumentos entra en modo escucha.
          - --list enumera interfaces HID y ayuda a encontrar colecciones vendor-defined.
          - --probe-interface intenta abrir y observar una interfaz HID concreta del dispositivo filtrado.
          - --probe-all-interfaces observa todas las interfaces HID del dispositivo filtrado sin consultar feature reports.
          - --dump-interface vuelca el report descriptor HID de una interfaz concreta.
          - --usbhost-probe intenta leer un endpoint USB interrupt por debajo de IOHID.
          - --usbhost-capture intenta capturar el dispositivo USB en exclusiva; puede desconectar temporalmente el teclado hasta parar el proceso.
          - --razer-macro-on envía los comandos propietarios de OpenRazer para activar driver mode y macro mode.
          - --razer-macro-off revierte macro mode y vuelve a normal mode.
          - --razer-macro-listen activa macro mode y muestra solo eventos M1-M6.
          - --deathadder-v2-listen observa eventos especiales del DeathAdder V2 y filtra movimiento, rueda y clicks izquierdo/derecho.
          - --deathadder-v2-audit hace lo mismo, pero conserva campos vendor-defined para encontrar botones no expuestos como botones HID.
          - --deathadder-v2-fkey-listen escucha botones del DeathAdder V2 configurados en Synapse como F13-F24.
          - --deathadder-v2-fkey-debug muestra keyCode, caracteres y Unicode scalars de cualquier tecla vista por el event tap.
          - --deathadder-v2-buttons-listen muestra solo down/up de F13, F14 y botones laterales usage 0x04/0x05.
          - --listen muestra keyDown, keyUp y flagsChanged del sistema, no reportes HID RAW.
          - Los modos --probe-* y --deathadder-v2-listen observan valores HID y reportes de entrada RAW.
        """
    }
}

enum CLIError: Error, CustomStringConvertible {
    case help
    case missingValue(String)
    case invalidInteger(String, String)
    case invalidConfiguration(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case .help:
            return CLIOptions.helpText
        case .missingValue(let argument):
            return "Missing value for \(argument)\n\n\(CLIOptions.helpText)"
        case .invalidInteger(let argument, let value):
            return "Invalid integer for \(argument): \(value)\n\n\(CLIOptions.helpText)"
        case .invalidConfiguration(let message):
            return "\(message)\n\n\(CLIOptions.helpText)"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)\n\n\(CLIOptions.helpText)"
        }
    }
}

private func parseIntegerArgument(named name: String, at index: Int, in arguments: [String]) throws -> Int {
    guard index < arguments.count else {
        throw CLIError.missingValue(name)
    }

    let rawValue = arguments[index]
    if rawValue.hasPrefix("0x") || rawValue.hasPrefix("0X") {
        let digits = String(rawValue.dropFirst(2))
        guard let parsed = Int(digits, radix: 16) else {
            throw CLIError.invalidInteger(name, rawValue)
        }
        return parsed
    }

    guard let parsed = Int(rawValue) else {
        throw CLIError.invalidInteger(name, rawValue)
    }

    return parsed
}
