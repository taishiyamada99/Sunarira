import Foundation

enum InterfaceLanguage: String, Codable, CaseIterable, Identifiable {
    case english
    case japanese
    case german
    case spanish
    case french

    var id: String { rawValue }

    var nativeDisplayName: String {
        switch self {
        case .english:
            return "English"
        case .japanese:
            return "日本語"
        case .german:
            return "Deutsch"
        case .spanish:
            return "Español"
        case .french:
            return "Français"
        }
    }

    func localized(
        english: String,
        japanese: String,
        german: String? = nil,
        spanish: String? = nil,
        french: String? = nil
    ) -> String {
        switch self {
        case .english:
            return english
        case .japanese:
            return japanese
        case .german:
            return german ?? english
        case .spanish:
            return spanish ?? english
        case .french:
            return french ?? english
        }
    }
}

enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case mode1
    case mode2
    case mode3
    case mode4
    case mode5

    var id: String { rawValue }

    var modeIndex: Int {
        switch self {
        case .mode1: return 0
        case .mode2: return 1
        case .mode3: return 2
        case .mode4: return 3
        case .mode5: return 4
        }
    }

    var hotKeyID: UInt32 {
        UInt32(modeIndex + 1)
    }

    init?(hotKeyID: UInt32) {
        let index = Int(hotKeyID) - 1
        guard index >= 0, index < HotkeyAction.allCases.count else {
            return nil
        }
        self = HotkeyAction.allCases[index]
    }

    static func forModeIndex(_ index: Int) -> HotkeyAction? {
        guard index >= 0, index < HotkeyAction.allCases.count else {
            return nil
        }
        return HotkeyAction.allCases[index]
    }
}

enum TransformPhase: Equatable {
    case idle
    case capturingInput
    case awaitingModelResponse
    case applyingOutput
}
