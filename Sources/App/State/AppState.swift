import Combine
import Foundation
import ServiceManagement
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
    @Published var launchAtLoginStatusMessage: String?
    @Published private(set) var accessibilityTrusted: Bool

    private let defaults: UserDefaults
    private let modelCatalogService: any ModelCatalogServiceProtocol
    private let accessibilityService: AccessibilityService
    private let preferencesKey = "sunarira.preferences"
    private let runtimeLogLimit = 300
    private let accessibilityPollInterval: TimeInterval = 0.8
    private let accessibilityPollTolerance: TimeInterval = 0.25
    private var accessibilityPollCancellable: AnyCancellable?
    private var runtimeLogUpdateCancellable: AnyCancellable?
    private var isRuntimeLogStreamingEnabled = false
    private var cancellables = Set<AnyCancellable>()

    init(
        defaults: UserDefaults = .standard,
        modelCatalogService: any ModelCatalogServiceProtocol = ModelCatalogService(),
        accessibilityService: AccessibilityService = AccessibilityService()
    ) {
        self.defaults = defaults
        self.modelCatalogService = modelCatalogService
        self.accessibilityService = accessibilityService
        accessibilityTrusted = accessibilityService.isTrusted(promptIfNeeded: false)

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
        validateHotkeyConflicts()
        refreshLaunchAtLoginState()
        refreshAccessibilityTrustStatus()
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
                english: "Keyboard shortcut must include at least one modifier key.",
                japanese: "キーボードショートカットには少なくとも1つの修飾キーが必要です。",
                german: "Ein Tastaturkurzbefehl muss mindestens eine Modifizierertaste enthalten.",
                spanish: "El atajo de teclado debe incluir al menos una tecla modificadora.",
                french: "Un raccourci clavier doit inclure au moins une touche de modification."
            )
            return
        }
        updatePreferences { prefs in
            prefs.hotkeys[action] = hotkey
        }
    }

    func hotkeyActionsForConfiguredModes() -> [HotkeyAction] {
        preferences.transformModes.indices.compactMap(HotkeyAction.forModeIndex(_:))
    }

    func modeForHotkeyAction(_ action: HotkeyAction) -> TransformModePreset? {
        let index = action.modeIndex
        guard index < preferences.transformModes.count else {
            return nil
        }
        return preferences.transformModes[index]
    }

    func registeredHotkeys() -> [HotkeyAction: Hotkey] {
        var registered: [HotkeyAction: Hotkey] = [:]
        for action in hotkeyActionsForConfiguredModes() {
            guard modeForHotkeyAction(action)?.isEnabled == true else { continue }
            let hotkey = hotkey(for: action)
            if hotkey.isValid {
                registered[action] = hotkey
            }
        }
        return registered
    }

    func hotkeyActionLabel(_ action: HotkeyAction) -> String {
        let number = action.modeIndex + 1
        let slot = localizedModeSlotLabel(number)
        if let mode = modeForHotkeyAction(action) {
            return "\(slot): \(mode.displayName)"
        }
        return slot
    }

    func selectMode(_ id: UUID) {
        updatePreferences { prefs in
            guard let mode = prefs.transformModes.first(where: { $0.id == id }), mode.isEnabled else { return }
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

            // Keep active mode selectable/executable.
            if !prefs.transformModes.contains(where: { $0.id == prefs.activeModeID && $0.isEnabled }) {
                if let fallback = prefs.transformModes.first(where: \.isEnabled) {
                    prefs.activeModeID = fallback.id
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
            if !prefs.transformModes.contains(where: \.isEnabled), !prefs.transformModes.isEmpty {
                prefs.transformModes[0].isEnabled = true
            }

            if let activeEnabled = prefs.transformModes.first(where: { $0.id == prefs.activeModeID && $0.isEnabled }) {
                prefs.activeModeID = activeEnabled.id
                return
            }
            if let firstEnabled = prefs.transformModes.first(where: \.isEnabled) {
                prefs.activeModeID = firstEnabled.id
                return
            }
            prefs.activeModeID = prefs.transformModes[0].id
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
        let refreshed = AppLogger.recentEntries(limit: runtimeLogLimit).joined(separator: "\n")
        if runtimeLogText != refreshed {
            runtimeLogText = refreshed
        }
    }

    func setRuntimeLogStreamingEnabled(_ enabled: Bool) {
        guard isRuntimeLogStreamingEnabled != enabled else {
            return
        }
        isRuntimeLogStreamingEnabled = enabled
        if enabled {
            startRuntimeLogStreaming()
            refreshRuntimeLogs()
        } else {
            stopRuntimeLogStreaming()
        }
    }

    func refreshAccessibilityTrustStatus() {
        let trusted = accessibilityService.isTrusted(promptIfNeeded: false)
        guard accessibilityTrusted != trusted else {
            return
        }
        accessibilityTrusted = trusted
    }

    func refreshLaunchAtLoginState() {
        guard !Self.isRunningTests else {
            launchAtLoginStatusMessage = nil
            return
        }
        applyLaunchAtLoginStatus(SMAppService.mainApp.status, requestedEnabled: nil)
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        guard !Self.isRunningTests else {
            updatePreferences { prefs in
                prefs.launchAtLogin = enabled
            }
            launchAtLoginStatusMessage = nil
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            applyLaunchAtLoginStatus(SMAppService.mainApp.status, requestedEnabled: enabled)
        } catch {
            applyLaunchAtLoginStatus(SMAppService.mainApp.status, requestedEnabled: nil)
            launchAtLoginStatusMessage = localizedUIString(
                english: "Could not update launch at login: \(error.localizedDescription)",
                japanese: "起動時に開始の設定を更新できませんでした: \(error.localizedDescription)",
                german: "Beim Aktualisieren von „Beim Anmelden starten“ ist ein Fehler aufgetreten: \(error.localizedDescription)",
                spanish: "No se pudo actualizar el inicio al iniciar sesión: \(error.localizedDescription)",
                french: "Impossible de mettre à jour le lancement à la connexion : \(error.localizedDescription)"
            )
        }
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
                japanese: "先にstdio起動コマンドを設定してください。",
                german: "Legen Sie zuerst einen stdio-Startbefehl fest.",
                spanish: "Primero configura un comando de inicio stdio.",
                french: "Définissez d'abord une commande de lancement stdio."
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
                    japanese: "model/list がモデルを返しませんでした。",
                    german: "model/list hat keine Modelle zurückgegeben.",
                    spanish: "model/list no devolvió modelos.",
                    french: "model/list n'a renvoyé aucun modèle."
                )
                return
            }

            modelRefreshMessage = localizedUIString(
                english: "Loaded \(models.count) model(s) from model/list.",
                japanese: "model/list から \(models.count) 件のモデルを読み込みました。",
                german: "\(models.count) Modell(e) aus model/list geladen.",
                spanish: "Se cargaron \(models.count) modelo(s) desde model/list.",
                french: "\(models.count) modèle(s) chargé(s) depuis model/list."
            )
        } catch {
            availableModels = []
            modelRefreshMessage = localizedUIString(
                english: "Model load failed: \(error.localizedDescription)",
                japanese: "モデル取得に失敗しました: \(error.localizedDescription)",
                german: "Modellladen fehlgeschlagen: \(error.localizedDescription)",
                spanish: "Error al cargar modelos: \(error.localizedDescription)",
                french: "Échec du chargement des modèles : \(error.localizedDescription)"
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

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(encoded, forKey: preferencesKey)
    }

    func startAccessibilityStatusPolling() {
        guard !Self.isRunningTests else {
            return
        }

        guard accessibilityPollCancellable == nil else {
            return
        }

        accessibilityPollCancellable = Timer.publish(
            every: accessibilityPollInterval,
            tolerance: accessibilityPollTolerance,
            on: .main,
            in: .common
        )
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshAccessibilityTrustStatus()
            }
    }

    func stopAccessibilityStatusPolling() {
        accessibilityPollCancellable?.cancel()
        accessibilityPollCancellable = nil
    }

    private func startRuntimeLogStreaming() {
        guard runtimeLogUpdateCancellable == nil else {
            return
        }
        runtimeLogUpdateCancellable = NotificationCenter.default.publisher(for: AppLogger.didUpdateNotification)
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshRuntimeLogs()
            }
    }

    private func stopRuntimeLogStreaming() {
        runtimeLogUpdateCancellable?.cancel()
        runtimeLogUpdateCancellable = nil
    }

    private func applyLaunchAtLoginStatus(_ status: SMAppService.Status, requestedEnabled: Bool?) {
        let resolvedEnabled: Bool
        let statusMessage: String?

        switch status {
        case .enabled:
            resolvedEnabled = true
            statusMessage = nil
        case .notRegistered:
            resolvedEnabled = false
            if requestedEnabled == true {
                statusMessage = localizedUIString(
                    english: "macOS did not keep this app in Login Items. Check System Settings > General > Login Items.",
                    japanese: "macOSでログイン項目への登録が完了しませんでした。システム設定 > 一般 > ログイン項目を確認してください。",
                    german: "macOS hat diese App nicht in den Anmeldeobjekten behalten. Prüfen Sie Systemeinstellungen > Allgemein > Anmeldeobjekte.",
                    spanish: "macOS no mantuvo esta app en Ítems de inicio. Revisa Ajustes del sistema > General > Ítems de inicio.",
                    french: "macOS n'a pas conservé cette app dans les éléments de connexion. Vérifiez Réglages Système > Général > Ouverture."
                )
            } else {
                statusMessage = nil
            }
        case .requiresApproval:
            resolvedEnabled = true
            statusMessage = localizedUIString(
                english: "Launch at login is pending approval in System Settings > General > Login Items.",
                japanese: "起動時に開始は承認待ちです。システム設定 > 一般 > ログイン項目で承認してください。",
                german: "„Beim Anmelden starten“ wartet auf Genehmigung in Systemeinstellungen > Allgemein > Anmeldeobjekte.",
                spanish: "El inicio al iniciar sesión está pendiente de aprobación en Ajustes del sistema > General > Ítems de inicio.",
                french: "Le lancement à la connexion attend une approbation dans Réglages Système > Général > Ouverture."
            )
        case .notFound:
            resolvedEnabled = false
            statusMessage = localizedUIString(
                english: "Launch at login is unavailable from this app location.",
                japanese: "このアプリの現在の配置では起動時に開始を利用できません。",
                german: "„Beim Anmelden starten“ ist von diesem App-Speicherort aus nicht verfügbar.",
                spanish: "El inicio al iniciar sesión no está disponible desde esta ubicación de la app.",
                french: "Le lancement à la connexion n'est pas disponible depuis cet emplacement de l'app."
            )
        @unknown default:
            resolvedEnabled = preferences.launchAtLogin
            statusMessage = localizedUIString(
                english: "Could not determine launch-at-login status.",
                japanese: "起動時に開始の状態を判定できませんでした。",
                german: "Der Status für „Beim Anmelden starten“ konnte nicht ermittelt werden.",
                spanish: "No se pudo determinar el estado del inicio al iniciar sesión.",
                french: "Impossible de déterminer l'état du lancement à la connexion."
            )
        }

        if preferences.launchAtLogin != resolvedEnabled {
            updatePreferences { prefs in
                prefs.launchAtLogin = resolvedEnabled
            }
        }

        launchAtLoginStatusMessage = statusMessage
    }

    private func validateHotkeyConflicts() {
        var seen: [Hotkey: HotkeyAction] = [:]
        for action in hotkeyActionsForConfiguredModes() {
            guard modeForHotkeyAction(action)?.isEnabled == true else { continue }
            let key = hotkey(for: action)
            if let duplicatedAction = seen[key] {
                hotkeyWarning = localizedUIString(
                    english: "Keyboard shortcut conflict: \(localizedHotkeyActionName(duplicatedAction)) and \(localizedHotkeyActionName(action)) share \(key.displayString).",
                    japanese: "キーボードショートカット競合: \(localizedHotkeyActionName(duplicatedAction)) と \(localizedHotkeyActionName(action)) が \(key.displayString) で重複しています。",
                    german: "Tastaturkurzbefehl-Konflikt: \(localizedHotkeyActionName(duplicatedAction)) und \(localizedHotkeyActionName(action)) verwenden beide \(key.displayString).",
                    spanish: "Conflicto de atajo de teclado: \(localizedHotkeyActionName(duplicatedAction)) y \(localizedHotkeyActionName(action)) usan \(key.displayString).",
                    french: "Conflit de raccourci clavier : \(localizedHotkeyActionName(duplicatedAction)) et \(localizedHotkeyActionName(action)) utilisent \(key.displayString)."
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

    private func localizedHotkeyActionName(_ action: HotkeyAction) -> String {
        hotkeyActionLabel(action)
    }

    private func localizedModeSlotLabel(_ number: Int) -> String {
        preferences.interfaceLanguage.localized(
            english: "Mode \(number)",
            japanese: "モード\(number)",
            german: "Modus \(number)",
            spanish: "Modo \(number)",
            french: "Mode \(number)"
        )
    }

    private func localizedUIString(
        english: String,
        japanese: String,
        german: String? = nil,
        spanish: String? = nil,
        french: String? = nil
    ) -> String {
        preferences.interfaceLanguage.localized(
            english: english,
            japanese: japanese,
            german: german,
            spanish: spanish,
            french: french
        )
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
