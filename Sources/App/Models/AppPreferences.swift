import Carbon.HIToolbox
import Foundation

struct TransformModePreset: Codable, Equatable, Identifiable {
    var id: UUID
    var displayName: String
    var promptTemplate: String
    var model: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        promptTemplate: String,
        model: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.promptTemplate = promptTemplate
        self.model = model
        self.isEnabled = isEnabled
    }
}

struct AppPreferences: Codable, Equatable {
    static let schemaVersionCurrent = 2
    static let minModeCount = 1
    static let maxModeCount = 5
    static let defaultModel = "gpt-5.2"

    var schemaVersion: Int
    var interfaceLanguage: InterfaceLanguage
    var transformModes: [TransformModePreset]
    var activeModeID: UUID
    var stdioCommand: String
    var hotkeys: [HotkeyAction: Hotkey]
    var includeSensitiveTextInLogs: Bool

    init(
        schemaVersion: Int = schemaVersionCurrent,
        interfaceLanguage: InterfaceLanguage,
        transformModes: [TransformModePreset],
        activeModeID: UUID,
        stdioCommand: String,
        hotkeys: [HotkeyAction: Hotkey],
        includeSensitiveTextInLogs: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.interfaceLanguage = interfaceLanguage
        self.transformModes = AppPreferences.normalizedModes(transformModes)
        self.activeModeID = activeModeID
        self.stdioCommand = stdioCommand
        self.hotkeys = hotkeys
        self.includeSensitiveTextInLogs = includeSensitiveTextInLogs
        sanitizeActiveMode()
    }

    static let `default`: AppPreferences = {
        let modes = defaultModes(model: defaultModel)
        return AppPreferences(
            interfaceLanguage: .english,
            transformModes: modes,
            activeModeID: modes[0].id,
            stdioCommand: "codex app-server --listen stdio://",
            hotkeys: [
                .transform: Hotkey(keyCode: 15, modifiers: UInt32(cmdKey | optionKey | controlKey)),
                .cycleMode: Hotkey(keyCode: 46, modifiers: UInt32(cmdKey | optionKey | controlKey))
            ],
            includeSensitiveTextInLogs: false
        )
    }()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case interfaceLanguage
        case transformModes
        case activeModeID
        case stdioCommand
        case hotkeys
        case includeSensitiveTextInLogs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppPreferences.default
        let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0

        // Reset legacy preferences (v0.1 schema) by design.
        guard schemaVersion >= AppPreferences.schemaVersionCurrent else {
            self = defaults
            return
        }

        self.schemaVersion = AppPreferences.schemaVersionCurrent
        interfaceLanguage = try container.decodeIfPresent(InterfaceLanguage.self, forKey: .interfaceLanguage) ?? defaults.interfaceLanguage
        transformModes = AppPreferences.normalizedModes(
            try container.decodeIfPresent([TransformModePreset].self, forKey: .transformModes) ?? defaults.transformModes
        )
        activeModeID = try container.decodeIfPresent(UUID.self, forKey: .activeModeID) ?? transformModes[0].id
        stdioCommand = try container.decodeIfPresent(String.self, forKey: .stdioCommand) ?? defaults.stdioCommand
        hotkeys = try container.decodeIfPresent([HotkeyAction: Hotkey].self, forKey: .hotkeys) ?? defaults.hotkeys
        includeSensitiveTextInLogs = try container.decodeIfPresent(Bool.self, forKey: .includeSensitiveTextInLogs) ?? defaults.includeSensitiveTextInLogs
        sanitizeActiveMode()
    }

    mutating func sanitize() {
        schemaVersion = AppPreferences.schemaVersionCurrent
        transformModes = AppPreferences.normalizedModes(transformModes)
        sanitizeActiveMode()

        if stdioCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stdioCommand = AppPreferences.default.stdioCommand
        }

        if hotkeys[.transform]?.isValid != true {
            hotkeys[.transform] = AppPreferences.default.hotkeys[.transform]
        }
        if hotkeys[.cycleMode]?.isValid != true {
            hotkeys[.cycleMode] = AppPreferences.default.hotkeys[.cycleMode]
        }
    }

    private mutating func sanitizeActiveMode() {
        if !transformModes.contains(where: { $0.id == activeModeID }) {
            activeModeID = transformModes[0].id
        }
    }

    private static func normalizedModes(_ modes: [TransformModePreset]) -> [TransformModePreset] {
        var normalized = modes.prefix(maxModeCount).map { mode in
            var next = mode
            next.displayName = next.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if next.displayName.isEmpty {
                next.displayName = "Mode"
            }
            next.model = next.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if next.model.isEmpty {
                next.model = defaultModel
            }
            return next
        }

        if normalized.isEmpty {
            normalized = [defaultModes(model: defaultModel)[0]]
        }

        while normalized.count < minModeCount {
            normalized.append(defaultModes(model: defaultModel)[0])
        }

        return normalized
    }

    static func defaultModes(model: String) -> [TransformModePreset] {
        [
            TransformModePreset(
                displayName: "汎用",
                promptTemplate: """
                入力文を、読みやすく分かりやすい自然な文章に書き換えてください。
                重要な事実・意図・次のアクションは保持してください。
                """,
                model: model
            ),
            TransformModePreset(
                displayName: "超端的",
                promptTemplate: """
                入力文を、可能な限り短く要約してください。
                重要度の低い補足情報は省略して構いません。
                """,
                model: model
            ),
            TransformModePreset(
                displayName: "意味保持短縮",
                promptTemplate: """
                入力文を、意味と重要情報を維持したまま短くしてください。
                重要な事実は省略しないでください。
                """,
                model: model
            )
        ]
    }
}
