import Foundation

public struct MacroKey: Identifiable {
    public let id: UInt8
    let name: String
    let mappedKey: String

    static let all: [MacroKey] = (0x20...0x25).map { code in
        MacroKey(
            id: UInt8(code),
            name: "M\(code - 0x20 + 1)",
            mappedKey: "F\(code - 0x20 + 13)"
        )
    }
}
