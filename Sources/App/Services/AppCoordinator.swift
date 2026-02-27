import Foundation

@MainActor
final class AppCoordinator {
    private let appState: AppState
    private let hotkeyManager: HotkeyManager
    private let accessibilityService: AccessibilityService
    private let notifier: UserNotifier
    private let axTextService: AXTextService
    private let clipboardFallbackService: ClipboardFallbackService
    private let transformService: TransformService

    private var isTransforming = false

    init(
        appState: AppState,
        hotkeyManager: HotkeyManager,
        accessibilityService: AccessibilityService,
        notifier: UserNotifier,
        axTextService: AXTextService,
        clipboardFallbackService: ClipboardFallbackService,
        transformService: TransformService
    ) {
        self.appState = appState
        self.hotkeyManager = hotkeyManager
        self.accessibilityService = accessibilityService
        self.notifier = notifier
        self.axTextService = axTextService
        self.clipboardFallbackService = clipboardFallbackService
        self.transformService = transformService

        hotkeyManager.onHotkeyPressed = { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleHotkeyAction(action)
            }
        }

        hotkeyManager.onRegistrationFailure = { [weak self] action, status in
            guard let self else { return }
            if self.appState.preferences.interfaceLanguage == .japanese {
                self.appState.hotkeyWarning = "\(action.displayName) の登録に失敗しました（status: \(status)）。既存ショートカットと競合している可能性があります。"
            } else {
                self.appState.hotkeyWarning = "Failed to register \(action.displayName) (status: \(status)). It may conflict with an existing shortcut."
            }
        }
    }

    func start() {
        registerHotkeys()
    }

    func registerHotkeys() {
        hotkeyManager.register(appState.preferences.hotkeys)
    }

    private func handleHotkeyAction(_ action: HotkeyAction) {
        switch action {
        case .transform:
            triggerTransform()
        case .cycleMode:
            appState.cycleMode()
            notifier.notify(title: localized("Mode", "モード"), message: appState.activeMode.displayName)
        }
    }

    func triggerTransform() {
        guard !isTransforming else { return }
        isTransforming = true
        appState.transformPhase = .capturingInput
        AppLogger.info("Transform triggered.")

        Task {
            defer {
                isTransforming = false
                appState.transformPhase = .idle
            }
            await performTransform()
        }
    }

    private func performTransform() async {
        do {
            appState.transformPhase = .capturingInput
            let capture = try axTextService.captureFocusedText()
            AppLogger.info("Captured text via AX. scope=\(capture.scope == .selection ? "selection" : "full"), length=\(capture.text.count)")
            AppLogger.payload("Captured input (AX)", text: capture.text)

            let contextPair = appState.transformContext(for: capture.text)
            if let fallbackFrom = contextPair.fallbackFrom {
                AppLogger.warning("Selected model unavailable. Fallback model=\(contextPair.context.model), selected=\(fallbackFrom)")
                notifier.notify(
                    title: localized("Model fallback", "モデルフォールバック"),
                    message: localized(
                        "Selected model is unavailable. Using \(contextPair.context.model).",
                        "選択モデルが利用不可のため \(contextPair.context.model) を使用します。"
                    )
                )
            }

            appState.transformPhase = .awaitingModelResponse
            let transformed = try await transformService.transform(input: capture.text, context: contextPair.context)
            AppLogger.payload("Transformed output (AX flow)", text: transformed)
            appState.transformPhase = .applyingOutput

            do {
                let method = try axTextService.replaceText(transformed, using: capture)
                AppLogger.info("Replaced text via \(method == .keystrokeInjection ? "keystroke injection" : "AX attribute set").")
                if method == .axAttributeSet {
                    notifier.notify(
                        title: localized("Text replaced", "テキスト置換"),
                        message: localized("Replaced via AX attribute set. Undo behavior may differ.", "AX属性設定で置換しました。Undo挙動が異なる場合があります。")
                    )
                }
            } catch {
                AppLogger.warning("AX replacement failed. Falling back to clipboard copy. error=\(error.localizedDescription)")
                axTextService.copyToClipboard(transformed)
                notifier.notify(
                    title: localized("Replace failed", "置換失敗"),
                    message: localized("Transformed text was copied to clipboard.", "変換結果をクリップボードへコピーしました。")
                )
            }
        } catch AXTextServiceError.accessibilityNotGranted {
            AppLogger.warning("AX capture failed: accessibility not granted.")
            await transformWithClipboardFallback(accessibilityGranted: false)
        } catch AXTextServiceError.focusedElementNotEditable {
            AppLogger.warning("AX capture failed: focused element is not editable text.")
            notifier.notify(
                title: localized("Transform canceled", "変換中止"),
                message: localized("Focus an editable text field and retry.", "編集可能なテキスト欄をフォーカスして再実行してください。")
            )
        } catch {
            AppLogger.warning("AX capture failed with error: \(error.localizedDescription). Trying focused-app clipboard fallback.")
            await transformWithClipboardFallback(accessibilityGranted: true)
        }
    }

    private func transformWithClipboardFallback(accessibilityGranted: Bool) async {
        if !accessibilityGranted {
            appState.transformPhase = .capturingInput
            let trusted = accessibilityService.isTrusted(promptIfNeeded: false)
            if !trusted {
                notifier.notify(
                    title: localized("Accessibility not granted", "アクセシビリティ未許可"),
                    message: localized("Grant Accessibility permission for direct in-place replace. Trying copy/paste fallback first.", "その場置換にはアクセシビリティ許可が必要です。先にコピー&ペーストのフォールバックを試します。")
                )
            }

            do {
                try await clipboardFallbackService.transformUsingFocusedAppClipboard { [self] input in
                    let contextPair = self.appState.transformContext(for: input)
                    AppLogger.payload("Captured input (clipboard fallback without AX)", text: input)
                    self.appState.transformPhase = .awaitingModelResponse
                    return try await self.transformService.transform(input: input, context: contextPair.context)
                }
                AppLogger.info("Focused-app clipboard fallback succeeded without AX permission.")
                appState.transformPhase = .applyingOutput
                return
            } catch {
                AppLogger.warning("Focused-app clipboard fallback without AX permission failed: \(error.localizedDescription)")
            }

            notifier.notify(
                title: localized("Transform canceled", "変換中止"),
                message: localized("Could not capture focused text. Clipboard-only fallback was skipped to avoid unintended replacement.", "フォーカステキストを取得できませんでした。意図しない置換を避けるためフォールバックを中断しました。")
            )
            return
        }

        notifier.notify(
            title: localized("Using clipboard fallback", "クリップボードフォールバック"),
            message: localized("AX read/replace failed. Trying copy/paste fallback.", "AX読み取り/置換に失敗したため、コピー&ペーストを試します。")
        )

        do {
            appState.transformPhase = .capturingInput
            try await clipboardFallbackService.transformUsingFocusedAppClipboard { [self] input in
                let contextPair = self.appState.transformContext(for: input)
                AppLogger.payload("Captured input (clipboard fallback)", text: input)
                self.appState.transformPhase = .awaitingModelResponse
                return try await self.transformService.transform(input: input, context: contextPair.context)
            }
            AppLogger.info("Focused-app clipboard fallback succeeded.")
            appState.transformPhase = .applyingOutput
        } catch {
            AppLogger.warning("Focused-app clipboard fallback failed: \(error.localizedDescription)")
            notifier.notify(title: localized("Transform failed", "変換失敗"), message: error.localizedDescription)
        }
    }

    private func localized(_ english: String, _ japanese: String) -> String {
        appState.preferences.interfaceLanguage == .japanese ? japanese : english
    }
}
