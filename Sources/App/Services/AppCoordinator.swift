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
    private let transformResultNotifier: TransformResultNotifier

    private var isTransforming = false

    init(
        appState: AppState,
        hotkeyManager: HotkeyManager,
        accessibilityService: AccessibilityService,
        notifier: UserNotifier,
        axTextService: AXTextService,
        clipboardFallbackService: ClipboardFallbackService,
        transformService: TransformService,
        transformResultNotifier: TransformResultNotifier
    ) {
        self.appState = appState
        self.hotkeyManager = hotkeyManager
        self.accessibilityService = accessibilityService
        self.notifier = notifier
        self.axTextService = axTextService
        self.clipboardFallbackService = clipboardFallbackService
        self.transformService = transformService
        self.transformResultNotifier = transformResultNotifier

        hotkeyManager.onHotkeyPressed = { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleHotkeyAction(action)
            }
        }

        hotkeyManager.onRegistrationFailure = { [weak self] action, status in
            guard let self else { return }
            let actionName = self.localizedHotkeyActionName(action)
            self.appState.hotkeyWarning = self.localized(
                "Failed to register \(actionName) (status: \(status)). It may conflict with an existing keyboard shortcut.",
                "\(actionName) の登録に失敗しました（status: \(status)）。既存のキーボードショートカットと競合している可能性があります。",
                "Registrierung von \(actionName) fehlgeschlagen (Status: \(status)). Möglicherweise besteht ein Konflikt mit einem vorhandenen Tastaturkurzbefehl.",
                "No se pudo registrar \(actionName) (estado: \(status)). Puede entrar en conflicto con un atajo de teclado existente.",
                "Échec de l'enregistrement de \(actionName) (statut : \(status)). Cela peut entrer en conflit avec un raccourci clavier existant."
            )
        }
    }

    func start() {
        registerHotkeys()
    }

    func registerHotkeys() {
        hotkeyManager.register(appState.registeredHotkeys())
    }

    private func handleHotkeyAction(_ action: HotkeyAction) {
        guard let mode = appState.modeForHotkeyAction(action) else {
            AppLogger.warning("Hotkey action \(action.rawValue) has no matching mode. Ignoring.")
            return
        }
        guard mode.isEnabled else {
            AppLogger.warning("Hotkey action \(action.rawValue) matched disabled mode '\(mode.displayName)'. Ignoring.")
            return
        }
        guard !isTransforming else { return }
        appState.selectMode(mode.id)
        triggerTransform()
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
                    title: localized("Model fallback", "モデルフォールバック", "Modell-Fallback", "Modelo alternativo", "Modèle de secours"),
                    message: localized(
                        "Selected model is unavailable. Using \(contextPair.context.model).",
                        "選択モデルが利用不可のため \(contextPair.context.model) を使用します。",
                        "Das ausgewählte Modell ist nicht verfügbar. \(contextPair.context.model) wird verwendet.",
                        "El modelo seleccionado no está disponible. Se usará \(contextPair.context.model).",
                        "Le modèle sélectionné n'est pas disponible. Utilisation de \(contextPair.context.model)."
                    )
                )
            }

            appState.transformPhase = .awaitingModelResponse
            let transformStart = DispatchTime.now().uptimeNanoseconds
            let transformed = try await transformService.transform(input: capture.text, context: contextPair.context)
            let transformElapsedMs = elapsedMilliseconds(sinceUptimeNanoseconds: transformStart)
            AppLogger.payload("Transformed output (AX flow)", text: transformed)
            appState.transformPhase = .applyingOutput

            do {
                let method = try axTextService.replaceText(transformed, using: capture)
                AppLogger.info("Replaced text via \(method == .keystrokeInjection ? "keystroke injection" : "AX attribute set").")
                if method == .axAttributeSet {
                    notifier.notify(
                        title: localized("Text replaced", "テキスト置換", "Text ersetzt", "Texto reemplazado", "Texte remplacé"),
                        message: localized(
                            "Replaced via AX attribute set. Undo behavior may differ.",
                            "AX属性設定で置換しました。Undo挙動が異なる場合があります。",
                            "Per AX-Attributsetzung ersetzt. Das Rückgängig-Verhalten kann abweichen.",
                            "Reemplazado mediante ajuste de atributo AX. El comportamiento de deshacer puede variar.",
                            "Remplacé via le réglage d'attribut AX. Le comportement d'annulation peut varier."
                        )
                    )
                }
            } catch {
                AppLogger.warning("AX replacement failed. Falling back to clipboard copy. error=\(error.localizedDescription)")
                axTextService.copyToClipboard(transformed)
                notifier.notify(
                    title: localized("Replace failed", "置換失敗", "Ersetzen fehlgeschlagen", "Error al reemplazar", "Échec du remplacement"),
                    message: localized(
                        "Transformed text was copied to clipboard.",
                        "変換結果をクリップボードへコピーしました。",
                        "Der umgeformte Text wurde in die Zwischenablage kopiert.",
                        "El texto transformado se copió al portapapeles.",
                        "Le texte transformé a été copié dans le presse-papiers."
                    )
                )
            }

            transformResultNotifier.notify(
                sourceText: capture.text,
                resultText: transformed,
                elapsedMilliseconds: transformElapsedMs
            )
        } catch AXTextServiceError.accessibilityNotGranted {
            AppLogger.warning("AX capture failed: accessibility not granted.")
            await transformWithClipboardFallback(accessibilityGranted: false)
        } catch AXTextServiceError.focusedElementNotEditable {
            AppLogger.warning("AX capture failed: focused element is not editable text.")
            notifier.notify(
                title: localized("Transform canceled", "変換中止", "Umformung abgebrochen", "Transformación cancelada", "Transformation annulée"),
                message: localized(
                    "Focus an editable text field and retry.",
                    "編集可能なテキスト欄をフォーカスして再実行してください。",
                    "Fokussieren Sie ein bearbeitbares Textfeld und versuchen Sie es erneut.",
                    "Enfoca un campo de texto editable y vuelve a intentarlo.",
                    "Sélectionnez un champ de texte modifiable et réessayez."
                )
            )
            transformResultNotifier.notifyFailure()
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
                    title: localized("Accessibility not granted", "アクセシビリティ未許可", "Bedienungshilfen nicht gewährt", "Accesibilidad no concedida", "Accessibilité non accordée"),
                    message: localized(
                        "Grant Accessibility permission for direct in-place replace. Trying copy/paste fallback first.",
                        "その場置換にはアクセシビリティ許可が必要です。先にコピー&ペーストのフォールバックを試します。",
                        "Erteilen Sie die Bedienungshilfen-Berechtigung für direktes Ersetzen. Zuerst wird der Kopieren/Einfügen-Fallback versucht.",
                        "Concede permiso de Accesibilidad para reemplazo directo en el lugar. Primero se intentará el método alternativo de copiar/pegar.",
                        "Accordez l'autorisation Accessibilité pour le remplacement direct sur place. Le mode de secours copier/coller sera d'abord essayé."
                    )
                )
            }

            do {
                var sourceTextForNotification: String?
                var transformedTextForNotification: String?
                var transformElapsedMsForNotification: Int?
                try await clipboardFallbackService.transformUsingFocusedAppClipboard { [self] input in
                    let contextPair = self.appState.transformContext(for: input)
                    AppLogger.payload("Captured input (clipboard fallback without AX)", text: input)
                    self.appState.transformPhase = .awaitingModelResponse
                    let transformStart = DispatchTime.now().uptimeNanoseconds
                    let transformed = try await self.transformService.transform(input: input, context: contextPair.context)
                    transformElapsedMsForNotification = self.elapsedMilliseconds(sinceUptimeNanoseconds: transformStart)
                    sourceTextForNotification = input
                    transformedTextForNotification = transformed
                    return transformed
                }
                AppLogger.info("Focused-app clipboard fallback succeeded without AX permission.")
                appState.transformPhase = .applyingOutput
                if
                    let sourceTextForNotification,
                    let transformedTextForNotification,
                    let transformElapsedMsForNotification
                {
                    transformResultNotifier.notify(
                        sourceText: sourceTextForNotification,
                        resultText: transformedTextForNotification,
                        elapsedMilliseconds: transformElapsedMsForNotification
                    )
                }
                return
            } catch {
                AppLogger.warning("Focused-app clipboard fallback without AX permission failed: \(error.localizedDescription)")
            }

            notifier.notify(
                title: localized("Transform canceled", "変換中止", "Umformung abgebrochen", "Transformación cancelada", "Transformation annulée"),
                message: localized(
                    "Could not capture focused text. Clipboard-only fallback was skipped to avoid unintended replacement.",
                    "フォーカステキストを取得できませんでした。意図しない置換を避けるためフォールバックを中断しました。",
                    "Der fokussierte Text konnte nicht erfasst werden. Der reine Zwischenablagen-Fallback wurde übersprungen, um unbeabsichtigtes Ersetzen zu vermeiden.",
                    "No se pudo capturar el texto enfocado. Se omitió el método alternativo solo con portapapeles para evitar reemplazos no deseados.",
                    "Impossible de capturer le texte ciblé. Le mode de secours basé uniquement sur le presse-papiers a été ignoré pour éviter un remplacement non souhaité."
                )
            )
            transformResultNotifier.notifyFailure(reason: .accessibilityNotGranted)
            return
        }

        notifier.notify(
            title: localized("Using clipboard fallback", "クリップボードフォールバック", "Zwischenablagen-Fallback wird verwendet", "Usando alternativa de portapapeles", "Utilisation du mode de secours presse-papiers"),
            message: localized(
                "AX read/replace failed. Trying copy/paste fallback.",
                "AX読み取り/置換に失敗したため、コピー&ペーストを試します。",
                "AX-Lesen/Ersetzen fehlgeschlagen. Kopieren/Einfügen-Fallback wird versucht.",
                "Falló la lectura/reemplazo por AX. Se intentará la alternativa de copiar/pegar.",
                "Échec de la lecture/remplacement AX. Tentative du mode de secours copier/coller."
            )
        )

        do {
            appState.transformPhase = .capturingInput
            var sourceTextForNotification: String?
            var transformedTextForNotification: String?
            var transformElapsedMsForNotification: Int?
            try await clipboardFallbackService.transformUsingFocusedAppClipboard { [self] input in
                let contextPair = self.appState.transformContext(for: input)
                AppLogger.payload("Captured input (clipboard fallback)", text: input)
                self.appState.transformPhase = .awaitingModelResponse
                let transformStart = DispatchTime.now().uptimeNanoseconds
                let transformed = try await self.transformService.transform(input: input, context: contextPair.context)
                transformElapsedMsForNotification = self.elapsedMilliseconds(sinceUptimeNanoseconds: transformStart)
                sourceTextForNotification = input
                transformedTextForNotification = transformed
                return transformed
            }
            AppLogger.info("Focused-app clipboard fallback succeeded.")
            appState.transformPhase = .applyingOutput
            if
                let sourceTextForNotification,
                let transformedTextForNotification,
                let transformElapsedMsForNotification
            {
                transformResultNotifier.notify(
                    sourceText: sourceTextForNotification,
                    resultText: transformedTextForNotification,
                    elapsedMilliseconds: transformElapsedMsForNotification
                )
            }
        } catch {
            AppLogger.warning("Focused-app clipboard fallback failed: \(error.localizedDescription)")
            notifier.notify(
                title: localized("Transform failed", "変換失敗", "Umformung fehlgeschlagen", "Transformación fallida", "Échec de la transformation"),
                message: error.localizedDescription
            )
            transformResultNotifier.notifyFailure()
        }
    }

    private func elapsedMilliseconds(sinceUptimeNanoseconds start: UInt64) -> Int {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= start else { return 0 }
        return Int((now - start) / 1_000_000)
    }

    private func localizedHotkeyActionName(_ action: HotkeyAction) -> String {
        appState.hotkeyActionLabel(action)
    }

    private func localized(
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
}
