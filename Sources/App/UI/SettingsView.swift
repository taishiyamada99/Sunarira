import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    let accessibilityService: AccessibilityService
    let onReRegisterHotkeys: () -> Void

    var body: some View {
        Form {
            Section(sectionInterface) {
                Picker(labelLanguage, selection: binding(\.interfaceLanguage)) {
                    ForEach(InterfaceLanguage.allCases) { language in
                        Text(interfaceLanguageName(language)).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(sectionModes) {
                HStack {
                    Text("\(labelCurrentMode): \(appState.activeMode.displayName)")
                        .font(.subheadline)
                    Spacer()
                    Button(buttonAddMode) {
                        appState.addMode()
                    }
                    .disabled(appState.preferences.transformModes.count >= AppPreferences.maxModeCount)
                }

                ForEach(Array(appState.preferences.transformModes.enumerated()), id: \.element.id) { index, mode in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(labelMode) \(index + 1)")
                                .font(.headline)
                            if appState.activeMode.id == mode.id {
                                Text(t("Active", "有効中"))
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            Toggle(t("Enabled", "有効"), isOn: modeEnabledBinding(mode.id))
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
                            .disabled(appState.activeMode.id == mode.id)

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
                            }
                            .disabled(appState.preferences.transformModes.count <= AppPreferences.minModeCount)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

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

            Section(sectionShortcuts) {
                ForEach(HotkeyAction.allCases) { action in
                    HotkeyRecorderRow(
                        title: hotkeyActionName(action),
                        hotkey: appState.hotkey(for: action)
                    ) { newHotkey in
                        appState.setHotkey(newHotkey, for: action)
                        onReRegisterHotkeys()
                    }
                }

                if let warning = appState.hotkeyWarning {
                    Text(warning)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
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
        .formStyle(.grouped)
        .padding(12)
        .frame(minWidth: 760, minHeight: 860)
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
            }
        )
    }

    private var isJapanese: Bool {
        appState.preferences.interfaceLanguage == .japanese
    }

    private var sectionInterface: String { t("Interface", "表示") }
    private var sectionModes: String { t("Transform Modes", "変換モード") }
    private var sectionEndpoint: String { t("App Server", "App Server") }
    private var sectionShortcuts: String { t("Shortcuts", "ショートカット") }
    private var sectionAccessibility: String { t("Accessibility", "アクセシビリティ") }
    private var sectionLogs: String { t("Logs", "ログ") }

    private var labelLanguage: String { t("Language", "言語") }
    private var labelMode: String { t("Mode", "モード") }
    private var labelCurrentMode: String { t("Current mode", "現在モード") }
    private var labelDisplayName: String { t("Display name", "表示名") }
    private var labelPrompt: String { t("Prompt template", "プロンプト") }
    private var labelModel: String { t("Model", "モデル") }

    private var placeholderStdioCommand: String { t("Stdio launch command", "stdio起動コマンド") }
    private var hintStdioCommand: String { t("Example: codex app-server --listen stdio://", "例: codex app-server --listen stdio://") }
    private var hintStdioSecurity: String { t("Security note: This command runs in your shell with your user permissions. Use trusted commands only.", "セキュリティ注意: このコマンドはシェル上で現在ユーザー権限で実行されます。信頼できるコマンドのみ使用してください。") }
    private var buttonRefreshModels: String { t("Refresh Models", "モデル再取得") }
    private var buttonAddMode: String { t("Add Mode", "モード追加") }
    private var buttonDeleteMode: String { t("Delete", "削除") }
    private var buttonSetActive: String { t("Set Active", "現在モードに設定") }
    private var buttonMoveUp: String { t("Move Up", "上へ") }
    private var buttonMoveDown: String { t("Move Down", "下へ") }

    private var buttonOpenAccessibilitySettings: String { t("Open Accessibility Settings", "アクセシビリティ設定を開く") }
    private var buttonCheckAccessibilityAgain: String { t("Check Again", "再確認") }
    private var toggleSensitiveLogText: String { t("Include input/output text in logs", "ログに入力/出力テキストを含める") }
    private var hintSensitiveLogText: String { t("Off by default. Turn on only while debugging because logs may contain sensitive text.", "既定はオフです。機密テキストがログに含まれるため、デバッグ時のみオンにしてください。") }
    private var buttonRefreshLogs: String { t("Refresh Logs", "ログ再読み込み") }
    private var buttonClearLogs: String { t("Clear Logs", "ログ消去") }
    private var emptyLogText: String { t("No logs yet.", "まだログはありません。") }

    private func t(_ english: String, _ japanese: String) -> String {
        isJapanese ? japanese : english
    }

    private func interfaceLanguageName(_ language: InterfaceLanguage) -> String {
        switch language {
        case .english:
            return isJapanese ? "英語" : "English"
        case .japanese:
            return isJapanese ? "日本語" : "Japanese"
        }
    }

    private func hotkeyActionName(_ action: HotkeyAction) -> String {
        switch action {
        case .transform:
            return t("Transform", "変換実行")
        case .cycleMode:
            return t("Mode cycle", "モード切替")
        }
    }

    private func accessibilityStatusText(_ trusted: Bool) -> String {
        trusted ? t("Status: OK", "状態: 許可済み") : t("Status: Not granted", "状態: 未許可")
    }
}
