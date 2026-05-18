import Foundation

enum RazerDeviceSelection: String, CaseIterable, Identifiable {
    case keyboard
    case mouse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyboard:
            return "BlackWidow V4 X"
        case .mouse:
            return "DeathAdder V2"
        }
    }

    var disconnectedTitle: String {
        switch self {
        case .keyboard:
            return "Razer keyboard not found"
        case .mouse:
            return "Razer mouse not found"
        }
    }
}
