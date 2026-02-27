import Foundation

enum InterfaceLanguage: String, Codable, CaseIterable, Identifiable {
    case english
    case japanese

    var id: String { rawValue }
}

enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case transform
    case cycleMode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .transform: return "Transform"
        case .cycleMode: return "Mode cycle"
        }
    }

    var hotKeyID: UInt32 {
        switch self {
        case .transform: return 1
        case .cycleMode: return 2
        }
    }

    init?(hotKeyID: UInt32) {
        switch hotKeyID {
        case 1: self = .transform
        case 2: self = .cycleMode
        default: return nil
        }
    }
}

enum TransformPhase: Equatable {
    case idle
    case capturingInput
    case awaitingModelResponse
    case applyingOutput
}
