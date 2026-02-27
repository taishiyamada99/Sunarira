import AppKit
import Combine
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let accessibilityService: AccessibilityService
    private let onTransform: () -> Void
    private let onOpenSettings: () -> Void
    private let onReRegisterHotkeys: () -> Void

    private let statusItem: NSStatusItem
    private var activeMenu: NSMenu?
    private var cancellables = Set<AnyCancellable>()

    init(
        appState: AppState,
        accessibilityService: AccessibilityService,
        onTransform: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onReRegisterHotkeys: @escaping () -> Void
    ) {
        self.appState = appState
        self.accessibilityService = accessibilityService
        self.onTransform = onTransform
        self.onOpenSettings = onOpenSettings
        self.onReRegisterHotkeys = onReRegisterHotkeys
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        setupButtonActions()
        bindState()
        refresh()
    }

    func refresh() {
        if let button = statusItem.button {
            button.title = ""
            button.image = statusImage()
            button.imagePosition = .imageOnly
            button.toolTip = statusToolTip()
        }
    }

    private func setupButtonActions() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(didTapStatusButton)
    }

    private func bindState() {
        appState.$preferences
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        appState.$hotkeyWarning
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        appState.$transformPhase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let transformItem = NSMenuItem(
            title: localized("Transform Now", "今すぐ変換", "Jetzt umformen", "Transformar ahora", "Transformer maintenant"),
            action: #selector(didTapTransform),
            keyEquivalent: ""
        )
        transformItem.target = self
        menu.addItem(transformItem)

        let currentModeItem = NSMenuItem(
            title: "\(localized("Current Mode", "現在モード", "Aktueller Modus", "Modo actual", "Mode actuel")): \(appState.activeMode.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        currentModeItem.isEnabled = false
        menu.addItem(currentModeItem)

        menu.addItem(makeModeMenuItem())
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: localized("Open Settings...", "設定を開く...", "Einstellungen öffnen...", "Abrir ajustes...", "Ouvrir les réglages..."),
            action: #selector(didTapOpenSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let reRegisterItem = NSMenuItem(
            title: localized("Re-register Keyboard Shortcuts", "キーボードショートカットを再登録", "Tastaturkurzbefehle neu registrieren", "Volver a registrar atajos de teclado", "Réenregistrer les raccourcis clavier"),
            action: #selector(didTapReRegisterHotkeys),
            keyEquivalent: ""
        )
        reRegisterItem.target = self
        menu.addItem(reRegisterItem)

        let trusted = accessibilityService.isTrusted(promptIfNeeded: false)
        let accessibilityItem = NSMenuItem(
            title: trusted
                ? localized("Accessibility: OK", "アクセシビリティ: 許可済み", "Bedienungshilfen: OK", "Accesibilidad: OK", "Accessibilité : OK")
                : localized("Accessibility: Not granted", "アクセシビリティ: 未許可", "Bedienungshilfen: Nicht gewährt", "Accesibilidad: No concedido", "Accessibilité : Non accordé"),
            action: #selector(didTapAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        if let warning = appState.hotkeyWarning {
            let warningItem = NSMenuItem(
                title: localized("Warning", "警告", "Warnung", "Advertencia", "Avertissement") + ": \(warning)",
                action: nil,
                keyEquivalent: ""
            )
            warningItem.isEnabled = false
            menu.addItem(warningItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: localized("Quit", "終了", "Beenden", "Salir", "Quitter"),
            action: #selector(didTapQuit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makeModeMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: localized("Modes", "モード", "Modi", "Modos", "Modes"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for mode in appState.preferences.transformModes {
            let title = mode.isEnabled
                ? mode.displayName
                : "\(mode.displayName) (\(localized("Disabled", "無効", "Deaktiviert", "Desactivado", "Désactivé")))"
            let item = NSMenuItem(title: title, action: #selector(didSelectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.id.uuidString
            item.state = appState.activeMode.id == mode.id ? .on : .off
            item.isEnabled = mode.isEnabled
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    private func statusImage() -> NSImage {
        let symbol = statusSymbolName()
        let fallback = "circle.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: statusToolTip())
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: statusToolTip())
            ?? NSImage()
        image.isTemplate = true
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return image.withSymbolConfiguration(configuration) ?? image
    }

    private func statusSymbolName() -> String {
        switch appState.transformPhase {
        case .idle:
            return appState.hotkeyWarning == nil ? "circle.fill" : "exclamationmark.triangle.fill"
        case .capturingInput:
            return "arrow.triangle.2.circlepath.circle"
        case .awaitingModelResponse:
            return "hourglass.circle"
        case .applyingOutput:
            return "square.and.pencil"
        }
    }

    private func statusToolTip() -> String {
        var lines = [
            "\(localized("Status", "状態", "Status", "Estado", "État")): \(transformPhaseName(appState.transformPhase))",
            "\(localized("Mode", "モード", "Modus", "Modo", "Mode")): \(appState.activeMode.displayName)",
            "\(localized("Model", "モデル", "Modell", "Modelo", "Modèle")): \(appState.activeMode.model)"
        ]
        if let warning = appState.hotkeyWarning {
            lines.append("\(localized("Warning", "警告", "Warnung", "Advertencia", "Avertissement")): \(warning)")
        }
        return lines.joined(separator: "\n")
    }

    private func transformPhaseName(_ phase: TransformPhase) -> String {
        switch phase {
        case .idle:
            return localized("Idle", "待機中", "Leerlauf", "En espera", "Inactif")
        case .capturingInput:
            return localized("Capturing text", "テキスト取得中", "Text wird erfasst", "Capturando texto", "Capture du texte")
        case .awaitingModelResponse:
            return localized("Waiting for AI response", "AI応答待ち", "Warten auf KI-Antwort", "Esperando respuesta de IA", "En attente de la réponse IA")
        case .applyingOutput:
            return localized("Applying result", "結果反映中", "Ergebnis wird angewendet", "Aplicando resultado", "Application du résultat")
        }
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

    @objc private func didTapStatusButton(_ sender: NSStatusBarButton) {
        let menu = buildMenu()
        menu.delegate = self
        activeMenu = menu
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    @objc private func didTapTransform() {
        onTransform()
    }

    @objc private func didTapOpenSettings() {
        onOpenSettings()
    }

    @objc private func didTapAccessibilitySettings() {
        accessibilityService.openAccessibilitySettings()
    }

    @objc private func didTapReRegisterHotkeys() {
        onReRegisterHotkeys()
    }

    @objc private func didTapQuit() {
        NSApp.terminate(nil)
    }

    @objc private func didSelectMode(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let id = UUID(uuidString: raw),
            let mode = appState.preferences.transformModes.first(where: { $0.id == id }),
            mode.isEnabled
        else { return }
        appState.selectMode(id)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard activeMenu === menu else { return }
        statusItem.menu = nil
        activeMenu = nil
    }
}
