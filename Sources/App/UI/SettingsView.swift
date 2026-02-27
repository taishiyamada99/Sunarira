import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let accessibilityService: AccessibilityService
    let onReRegisterHotkeys: () -> Void
    @State private var showAdminSettings = false

    var body: some View {
        Form {
            Section(sectionInterface) {
                Picker(labelLanguage, selection: binding(\.interfaceLanguage)) {
                    ForEach(InterfaceLanguage.allCases) { language in
                        Text(interfaceLanguageName(language)).tag(language)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(sectionModes) {
                HStack {
                    Text("\(labelCurrentMode): \(appState.activeMode.displayName)")
                        .font(.subheadline)
                    Spacer()
                    Button(buttonAddMode) {
                        appState.addMode()
                        onReRegisterHotkeys()
                    }
                    .disabled(appState.preferences.transformModes.count >= AppPreferences.maxModeCount)
                }

                ForEach(Array(appState.preferences.transformModes.enumerated()), id: \.element.id) { index, mode in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(labelMode) \(index + 1)")
                                .font(.headline)
                            if appState.activeMode.id == mode.id {
                                Text(t("Active", "有効中", "Aktiv", "Activo", "Actif"))
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Toggle(t("Enabled", "有効", "Aktiviert", "Habilitado", "Activé"), isOn: modeEnabledBinding(mode.id))
                                .labelsHidden()
                        }

                        TextField(
                            labelDisplayName,
                            text: modeDisplayNameBinding(mode.id)
                        )
                        .textFieldStyle(.roundedBorder)

                        Text(labelPrompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: modePromptBinding(mode.id))
                            .frame(minHeight: 90, maxHeight: 140)
                            .font(.system(.body, design: .monospaced))

                        Picker(labelModel, selection: modeModelBinding(mode.id)) {
                            ForEach(appState.modelOptions(including: mode.model), id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(.menu)

                        HStack {
                            Button(buttonSetActive) {
                                appState.selectMode(mode.id)
                            }
                            .disabled(appState.activeMode.id == mode.id || !mode.isEnabled)

                            Button(buttonMoveUp) {
                                appState.moveModeUp(id: mode.id)
                            }
                            .disabled(index == 0)

                            Button(buttonMoveDown) {
                                appState.moveModeDown(id: mode.id)
                            }
                            .disabled(index == appState.preferences.transformModes.count - 1)

                            Spacer()

                            Button(buttonDeleteMode, role: .destructive) {
                                appState.removeMode(id: mode.id)
                                onReRegisterHotkeys()
                            }
                            .disabled(appState.preferences.transformModes.count <= AppPreferences.minModeCount)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            Section(sectionShortcuts) {
                ForEach(Array(appState.preferences.transformModes.enumerated()), id: \.element.id) { index, _ in
                    if let action = HotkeyAction.forModeIndex(index) {
                        HotkeyRecorderRow(
                            title: appState.hotkeyActionLabel(action),
                            hotkey: appState.hotkey(for: action),
                            recordingLabel: recordingShortcutLabel
                        ) { newHotkey in
                            appState.setHotkey(newHotkey, for: action)
                            onReRegisterHotkeys()
                        }
                    }
                }

                if let warning = appState.hotkeyWarning {
                    Text(warning)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                Text(hintShortcutPerMode)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(sectionAccessibility) {
                let trusted = accessibilityService.isTrusted(promptIfNeeded: false)
                Text(accessibilityStatusText(trusted))
                HStack {
                    Button(buttonOpenAccessibilitySettings) {
                        accessibilityService.openAccessibilitySettings()
                    }
                    Button(buttonCheckAccessibilityAgain) {
                        _ = accessibilityService.isTrusted(promptIfNeeded: true)
                    }
                }
            }

            Section(sectionAdminMode) {
                if showAdminSettings {
                    HStack {
                        Text(labelAdminModeEnabled)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(buttonHideAdminMode) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAdminSettings = false
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(hintAdminModeEnabled)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(labelAdminModeDisabled)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(buttonShowAdminMode) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showAdminSettings = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Text(hintAdminModeDisabled)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showAdminSettings {
                Section(sectionEndpoint) {
                    TextField(placeholderStdioCommand, text: binding(\.stdioCommand))
                        .textFieldStyle(.roundedBorder)

                    Text(hintStdioCommand)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(hintStdioSecurity)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(buttonRefreshModels) {
                            Task {
                                await appState.refreshAvailableModels()
                            }
                        }
                        .disabled(appState.isRefreshingModels)

                        if appState.isRefreshingModels {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let message = appState.modelRefreshMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(sectionLogs) {
                    Toggle(toggleSensitiveLogText, isOn: binding(\.includeSensitiveTextInLogs))
                    Text(hintSensitiveLogText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(buttonRefreshLogs) {
                            appState.refreshRuntimeLogs()
                        }
                        Button(buttonClearLogs) {
                            appState.clearRuntimeLogs()
                        }
                    }

                    ScrollView {
                        Text(appState.runtimeLogText.isEmpty ? emptyLogText : appState.runtimeLogText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 180, maxHeight: 260)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(minWidth: 760, minHeight: showAdminSettings ? 860 : 700)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<AppPreferences, T>) -> Binding<T> {
        Binding(
            get: { appState.preferences[keyPath: keyPath] },
            set: { newValue in
                appState.updatePreferences { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func modeDisplayNameBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { appState.preferences.transformModes.first(where: { $0.id == id })?.displayName ?? "" },
            set: { newValue in
                appState.updateMode(id: id) { $0.displayName = newValue }
            }
        )
    }

    private func modePromptBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { appState.preferences.transformModes.first(where: { $0.id == id })?.promptTemplate ?? "" },
            set: { newValue in
                appState.updateMode(id: id) { $0.promptTemplate = newValue }
            }
        )
    }

    private func modeModelBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { appState.preferences.transformModes.first(where: { $0.id == id })?.model ?? AppPreferences.defaultModel },
            set: { newValue in
                appState.updateMode(id: id) { $0.model = newValue }
            }
        )
    }

    private func modeEnabledBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { appState.preferences.transformModes.first(where: { $0.id == id })?.isEnabled ?? true },
            set: { newValue in
                appState.updateMode(id: id) { $0.isEnabled = newValue }
                onReRegisterHotkeys()
            }
        )
    }

    private var sectionInterface: String { t("Interface", "表示", "Sprache", "Idioma", "Langue") }
    private var sectionModes: String { t("Transform Modes", "変換モード", "Transformationsmodi", "Modos de transformación", "Modes de transformation") }
    private var sectionEndpoint: String { t("App Server", "App Server", "App Server", "App Server", "App Server") }
    private var sectionShortcuts: String { t("Keyboard Shortcuts", "キーボードショートカット", "Tastaturkurzbefehle", "Atajos de teclado", "Raccourcis clavier") }
    private var sectionAccessibility: String { t("Accessibility", "アクセシビリティ", "Bedienungshilfen", "Accesibilidad", "Accessibilité") }
    private var sectionAdminMode: String { t("Administrator Mode", "管理者モード", "Administratormodus", "Modo administrador", "Mode administrateur") }
    private var sectionLogs: String { t("Logs", "ログ", "Protokolle", "Registros", "Journaux") }

    private var labelLanguage: String { t("Language", "言語", "Sprache", "Idioma", "Langue") }
    private var labelMode: String { t("Mode", "モード", "Modus", "Modo", "Mode") }
    private var labelCurrentMode: String { t("Current mode", "現在モード", "Aktueller Modus", "Modo actual", "Mode actuel") }
    private var labelDisplayName: String { t("Display name", "表示名", "Anzeigename", "Nombre visible", "Nom d'affichage") }
    private var labelPrompt: String { t("Prompt template", "プロンプト", "Prompt-Vorlage", "Plantilla de prompt", "Modèle de prompt") }
    private var labelModel: String { t("Model", "モデル", "Modell", "Modelo", "Modèle") }
    private var hintShortcutPerMode: String { t("Assign one keyboard shortcut per mode. Pressing a keyboard shortcut switches to that mode and runs transform.", "モードごとに1つのキーボードショートカットを割り当てできます。押すとそのモードに切り替えて変換を実行します。", "Weisen Sie jedem Modus einen Tastaturkurzbefehl zu. Beim Drücken wird zu diesem Modus gewechselt und die Umformung ausgeführt.", "Asigna un atajo de teclado por modo. Al pulsarlo se cambia a ese modo y se ejecuta la transformación.", "Attribuez un raccourci clavier par mode. En l'appuyant, l'application bascule vers ce mode et lance la transformation.") }
    private var recordingShortcutLabel: String { t("Press keyboard shortcut...", "キーボードショートカットを押してください...", "Tastaturkurzbefehl drücken...", "Pulsa el atajo de teclado...", "Appuyez sur le raccourci clavier...") }

    private var placeholderStdioCommand: String { t("Stdio launch command", "stdio起動コマンド", "Stdio-Startbefehl", "Comando de inicio stdio", "Commande de lancement stdio") }
    private var hintStdioCommand: String { t("Example: codex app-server --listen stdio://", "例: codex app-server --listen stdio://", "Beispiel: codex app-server --listen stdio://", "Ejemplo: codex app-server --listen stdio://", "Exemple : codex app-server --listen stdio://") }
    private var hintStdioSecurity: String { t("Security note: This command runs in your shell with your user permissions. Use trusted commands only.", "セキュリティ注意: このコマンドはシェル上で現在ユーザー権限で実行されます。信頼できるコマンドのみ使用してください。", "Sicherheitshinweis: Dieser Befehl wird in Ihrer Shell mit Ihren Benutzerrechten ausgeführt. Verwenden Sie nur vertrauenswürdige Befehle.", "Nota de seguridad: Este comando se ejecuta en tu shell con los permisos de tu usuario. Usa solo comandos de confianza.", "Note de sécurité : cette commande s'exécute dans votre shell avec vos autorisations utilisateur. N'utilisez que des commandes fiables.") }
    private var buttonRefreshModels: String { t("Refresh Models", "モデル再取得", "Modelle aktualisieren", "Actualizar modelos", "Actualiser les modèles") }
    private var buttonAddMode: String { t("Add Mode", "モード追加", "Modus hinzufügen", "Añadir modo", "Ajouter un mode") }
    private var buttonDeleteMode: String { t("Delete", "削除", "Löschen", "Eliminar", "Supprimer") }
    private var buttonSetActive: String { t("Set Active", "現在モードに設定", "Als aktiv setzen", "Establecer activo", "Définir actif") }
    private var buttonMoveUp: String { t("Move Up", "上へ", "Nach oben", "Subir", "Monter") }
    private var buttonMoveDown: String { t("Move Down", "下へ", "Nach unten", "Bajar", "Descendre") }
    private var buttonShowAdminMode: String { t("Show Advanced Settings", "高度な設定を表示", "Erweiterte Einstellungen anzeigen", "Mostrar ajustes avanzados", "Afficher les réglages avancés") }
    private var buttonHideAdminMode: String { t("Hide Advanced Settings", "高度な設定を隠す", "Erweiterte Einstellungen ausblenden", "Ocultar ajustes avanzados", "Masquer les réglages avancés") }
    private var labelAdminModeEnabled: String { t("Advanced settings are visible.", "高度な設定を表示中です。", "Erweiterte Einstellungen sind sichtbar.", "La configuración avanzada está visible.", "Les réglages avancés sont visibles.") }
    private var labelAdminModeDisabled: String { t("Advanced settings are hidden.", "高度な設定は非表示です。", "Erweiterte Einstellungen sind ausgeblendet.", "La configuración avanzada está oculta.", "Les réglages avancés sont masqués.") }
    private var hintAdminModeEnabled: String { t("App Server and Logs sections are available below.", "この下に App Server とログのセクションが表示されます。", "Die Bereiche App Server und Protokolle sind unten verfügbar.", "Las secciones App Server y Registros están disponibles abajo.", "Les sections App Server et Journaux sont disponibles ci-dessous.") }
    private var hintAdminModeDisabled: String { t("Open administrator mode to manage App Server and log details.", "App Server やログ詳細を扱うには管理者モードを開いてください。", "Öffnen Sie den Administratormodus, um App Server und Protokolldetails zu verwalten.", "Abre el modo administrador para gestionar App Server y detalles de registros.", "Ouvrez le mode administrateur pour gérer App Server et les détails des journaux.") }

    private var buttonOpenAccessibilitySettings: String { t("Open Accessibility Settings", "アクセシビリティ設定を開く", "Bedienungshilfen öffnen", "Abrir ajustes de accesibilidad", "Ouvrir les réglages d'accessibilité") }
    private var buttonCheckAccessibilityAgain: String { t("Check Again", "再確認", "Erneut prüfen", "Comprobar de nuevo", "Vérifier à nouveau") }
    private var toggleSensitiveLogText: String { t("Include input/output text in logs", "ログに入力/出力テキストを含める", "Eingabe-/Ausgabetext in Protokolle aufnehmen", "Incluir texto de entrada/salida en los registros", "Inclure le texte d'entrée/sortie dans les journaux") }
    private var hintSensitiveLogText: String { t("Off by default. Turn on only while debugging because logs may contain sensitive text.", "既定はオフです。機密テキストがログに含まれるため、デバッグ時のみオンにしてください。", "Standardmäßig aus. Nur zum Debuggen einschalten, da Protokolle sensible Texte enthalten können.", "Desactivado por defecto. Actívalo solo para depuración, ya que los registros pueden contener texto sensible.", "Désactivé par défaut. Activez-le uniquement pour le débogage, car les journaux peuvent contenir des textes sensibles.") }
    private var buttonRefreshLogs: String { t("Refresh Logs", "ログ再読み込み", "Protokolle aktualisieren", "Actualizar registros", "Actualiser les journaux") }
    private var buttonClearLogs: String { t("Clear Logs", "ログ消去", "Protokolle leeren", "Borrar registros", "Effacer les journaux") }
    private var emptyLogText: String { t("No logs yet.", "まだログはありません。", "Noch keine Protokolle.", "Aún no hay registros.", "Aucun journal pour l'instant.") }

    private func t(
        _ english: String,
        _ japanese: String,
        _ german: String? = nil,
        _ spanish: String? = nil,
        _ french: String? = nil
    ) -> String {
        appState.preferences.interfaceLanguage.localized(
            english: english,
            japanese: japanese,
            german: german,
            spanish: spanish,
            french: french
        )
    }

    private func interfaceLanguageName(_ language: InterfaceLanguage) -> String {
        language.nativeDisplayName
    }

    private func accessibilityStatusText(_ trusted: Bool) -> String {
        trusted
            ? t("Status: OK", "状態: 許可済み", "Status: OK", "Estado: OK", "État : OK")
            : t("Status: Not granted", "状態: 未許可", "Status: Nicht gewährt", "Estado: No concedido", "État : Non accordé")
    }
}
