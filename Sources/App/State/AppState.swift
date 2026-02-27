import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var preferences: AppPreferences {
        didSet {
            persist()
            validateHotkeyConflicts()
            AppLogger.setIncludeSensitiveText(preferences.includeSensitiveTextInLogs)
        }
    }

    @Published var hotkeyWarning: String?
    @Published var availableModels: [String] = []
    @Published var isRefreshingModels = false
    @Published var modelRefreshMessage: String?
    @Published var transformPhase: TransformPhase = .idle
    @Published var runtimeLogText: String = ""

    private let defaults: UserDefaults
    private let modelCatalogService: any ModelCatalogServiceProtocol
    private let preferencesKey = "sunarira.preferences"
    private let runtimeLogLimit = 300
    private var cancellables = Set<AnyCancellable>()

    init(
        defaults: UserDefaults = .standard,
        modelCatalogService: any ModelCatalogServiceProtocol = ModelCatalogService()
    ) {
        self.defaults = defaults
        self.modelCatalogService = modelCatalogService

        if
            let data = defaults.data(forKey: preferencesKey),
            let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data)
        {
            var sanitized = decoded
            sanitized.sanitize()
            preferences = sanitized
        } else {
            preferences = .default
        }

        AppLogger.setIncludeSensitiveText(preferences.includeSensitiveTextInLogs)
        runtimeLogText = AppLogger.recentEntries(limit: runtimeLogLimit).joined(separator: "\n")
        NotificationCenter.default.publisher(for: AppLogger.didUpdateNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshRuntimeLogs()
                }
            }
            .store(in: &cancellables)
        validateHotkeyConflicts()
    }

    var activeMode: TransformModePreset {
        preferences.transformModes.first(where: { $0.id == preferences.activeModeID }) ?? preferences.transformModes[0]
    }

    func updatePreferences(_ block: (inout AppPreferences) -> Void) {
        var next = preferences
        block(&next)
        next.sanitize()
        preferences = next
    }

    func hotkey(for action: HotkeyAction) -> Hotkey {
        preferences.hotkeys[action] ?? Hotkey.fallback
    }

    func setHotkey(_ hotkey: Hotkey, for action: HotkeyAction) {
        guard hotkey.isValid else {
            hotkeyWarning = localizedUIString(
                english: "Shortcut must include at least one modifier key.",
                japanese: "ショートカットには少なくとも1つの修飾キーが必要です。"
            )
            return
        }
        updatePreferences { prefs in
            prefs.hotkeys[action] = hotkey
        }
    }

    func cycleMode() {
        let modes = enabledModes()
        guard !modes.isEmpty else { return }

        let activeID = preferences.activeModeID
        guard let index = modes.firstIndex(where: { $0.id == activeID }) else {
            selectMode(modes[0].id)
            return
        }

        let next = modes[(index + 1) % modes.count]
        selectMode(next.id)
    }

    func selectMode(_ id: UUID) {
        updatePreferences { prefs in
            guard prefs.transformModes.contains(where: { $0.id == id }) else { return }
            prefs.activeModeID = id
        }
    }

    func updateMode(id: UUID, mutate: (inout TransformModePreset) -> Void) {
        updatePreferences { prefs in
            guard let index = prefs.transformModes.firstIndex(where: { $0.id == id }) else { return }
            mutate(&prefs.transformModes[index])

            if !prefs.transformModes[index].isEnabled {
                let hasEnabled = prefs.transformModes.contains { $0.isEnabled }
                if !hasEnabled {
                    prefs.transformModes[index].isEnabled = true
                }
            }
        }
    }

    func addMode() {
        updatePreferences { prefs in
            guard prefs.transformModes.count < AppPreferences.maxModeCount else { return }
            let index = prefs.transformModes.count + 1
            let model = recommendedDefaultModel(from: availableModels) ?? AppPreferences.defaultModel
            let mode = TransformModePreset(
                displayName: "Mode \(index)",
                promptTemplate: "Rewrite the input to be clearer and concise while preserving meaning.",
                model: model
            )
            prefs.transformModes.append(mode)
        }
    }

    func removeMode(id: UUID) {
        updatePreferences { prefs in
            guard prefs.transformModes.count > AppPreferences.minModeCount else { return }
            prefs.transformModes.removeAll { $0.id == id }
            if !prefs.transformModes.contains(where: { $0.id == prefs.activeModeID }) {
                prefs.activeModeID = prefs.transformModes[0].id
            }
        }
    }

    func moveModeUp(id: UUID) {
        updatePreferences { prefs in
            guard let index = prefs.transformModes.firstIndex(where: { $0.id == id }), index > 0 else { return }
            prefs.transformModes.swapAt(index, index - 1)
        }
    }

    func moveModeDown(id: UUID) {
        updatePreferences { prefs in
            guard let index = prefs.transformModes.firstIndex(where: { $0.id == id }), index + 1 < prefs.transformModes.count else { return }
            prefs.transformModes.swapAt(index, index + 1)
        }
    }

    func refreshRuntimeLogs() {
        runtimeLogText = AppLogger.recentEntries(limit: runtimeLogLimit).joined(separator: "\n")
    }

    func clearRuntimeLogs() {
        AppLogger.clear()
        refreshRuntimeLogs()
    }

    func refreshAvailableModels() async {
        let command = preferences.stdioCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            availableModels = []
            modelRefreshMessage = localizedUIString(
                english: "Set a stdio launch command first.",
                japanese: "先にstdio起動コマンドを設定してください。"
            )
            return
        }

        isRefreshingModels = true
        defer { isRefreshingModels = false }

        do {
            let models = try await modelCatalogService.fetchModels(stdioCommand: command)
            availableModels = models.sorted(by: isPreferredModel(_:over:))

            if models.isEmpty {
                modelRefreshMessage = localizedUIString(
                    english: "No models were returned by model/list.",
                    japanese: "model/list がモデルを返しませんでした。"
                )
                return
            }

            modelRefreshMessage = localizedUIString(
                english: "Loaded \(models.count) model(s) from model/list.",
                japanese: "model/list から \(models.count) 件のモデルを読み込みました。"
            )
        } catch {
            availableModels = []
            modelRefreshMessage = localizedUIString(
                english: "Model load failed: \(error.localizedDescription)",
                japanese: "モデル取得に失敗しました: \(error.localizedDescription)"
            )
        }
    }

    func resolveModel(for mode: TransformModePreset) -> (resolved: String, fallbackFrom: String?) {
        let selected = mode.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultModel = recommendedDefaultModel(from: availableModels) ?? AppPreferences.defaultModel

        guard !selected.isEmpty else {
            return (defaultModel, nil)
        }

        if availableModels.isEmpty || availableModels.contains(selected) {
            return (selected, nil)
        }

        return (defaultModel, selected)
    }

    func transformContext(for input: String, mode: TransformModePreset? = nil) -> (context: TransformContext, fallbackFrom: String?) {
        let effectiveMode = mode ?? activeMode
        let resolved = resolveModel(for: effectiveMode)
        let context = TransformContext(
            modeID: effectiveMode.id,
            modeDisplayName: effectiveMode.displayName,
            promptTemplate: effectiveMode.promptTemplate,
            model: resolved.resolved,
            inputText: input
        )
        return (context, resolved.fallbackFrom)
    }

    func modelOptions(including preferred: String? = nil) -> [String] {
        var options: [String] = []

        if let preferred {
            let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                options.append(trimmed)
            }
        }

        for mode in preferences.transformModes {
            let model = mode.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if !model.isEmpty, !options.contains(model) {
                options.append(model)
            }
        }

        for model in availableModels.sorted(by: isPreferredModel(_:over:)) where !model.isEmpty {
            if !options.contains(model) {
                options.append(model)
            }
        }

        if options.isEmpty {
            options = [AppPreferences.defaultModel]
        }

        return options
    }

    private func enabledModes() -> [TransformModePreset] {
        let enabled = preferences.transformModes.filter(\.isEnabled)
        return enabled.isEmpty ? [preferences.transformModes[0]] : enabled
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(encoded, forKey: preferencesKey)
    }

    private func validateHotkeyConflicts() {
        var seen: [Hotkey: HotkeyAction] = [:]
        for action in HotkeyAction.allCases {
            let key = hotkey(for: action)
            if let duplicatedAction = seen[key] {
                hotkeyWarning = localizedUIString(
                    english: "Shortcut conflict: \(duplicatedAction.displayName) and \(action.displayName) share \(key.displayString).",
                    japanese: "ショートカット競合: \(duplicatedAction.displayName) と \(action.displayName) が \(key.displayString) で重複しています。"
                )
                return
            }
            seen[key] = action
        }
        hotkeyWarning = nil
    }

    private func recommendedDefaultModel(from models: [String]) -> String? {
        let nonCodex = models.filter { !$0.lowercased().contains("codex") }
        let candidates = nonCodex.isEmpty ? models : nonCodex
        return candidates.sorted(by: isPreferredModel(_:over:)).first
    }

    private func isPreferredModel(_ lhs: String, over rhs: String) -> Bool {
        let left = modelSortKey(lhs)
        let right = modelSortKey(rhs)
        if left != right {
            return left > right
        }
        return lhs.localizedStandardCompare(rhs) == .orderedAscending
    }

    private func modelSortKey(_ model: String) -> (family: Int, major: Int, minor: Int, patch: Int) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let family: Int
        if trimmed.hasPrefix("gpt-") {
            family = 3
        } else if trimmed.contains("spark") {
            family = 2
        } else {
            family = 1
        }

        let numbers = trimmed.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let major = numbers.count > 0 ? numbers[0] : -1
        let minor = numbers.count > 1 ? numbers[1] : -1
        let patch = numbers.count > 2 ? numbers[2] : -1
        return (family, major, minor, patch)
    }

    private func localizedUIString(english: String, japanese: String) -> String {
        preferences.interfaceLanguage == .japanese ? japanese : english
    }
}
