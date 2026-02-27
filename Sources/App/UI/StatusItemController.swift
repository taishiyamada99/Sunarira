import AppKit
import Combine
import Foundation

@MainActor
final class StatusItemController: NSObject {
    private let appState: AppState
    private let accessibilityService: AccessibilityService
    private let onTransform: () -> Void
    private let onOpenSettings: () -> Void
    private let onReRegisterHotkeys: () -> Void

    private let statusItem: NSStatusItem
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
            title: localized("Transform Now", "今すぐ変換"),
            action: #selector(didTapTransform),
            keyEquivalent: ""
        )
        transformItem.target = self
        menu.addItem(transformItem)

        let currentModeItem = NSMenuItem(
            title: "\(localized("Current Mode", "現在モード")): \(appState.activeMode.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        currentModeItem.isEnabled = false
        menu.addItem(currentModeItem)

        menu.addItem(makeModeMenuItem())
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: localized("Open Settings...", "設定を開く..."),
            action: #selector(didTapOpenSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let reRegisterItem = NSMenuItem(
            title: localized("Re-register Hotkeys", "ホットキー再登録"),
            action: #selector(didTapReRegisterHotkeys),
            keyEquivalent: ""
        )
        reRegisterItem.target = self
        menu.addItem(reRegisterItem)

        let trusted = accessibilityService.isTrusted(promptIfNeeded: false)
        let accessibilityItem = NSMenuItem(
            title: trusted
                ? localized("Accessibility: OK", "アクセシビリティ: 許可済み")
                : localized("Accessibility: Not granted", "アクセシビリティ: 未許可"),
            action: #selector(didTapAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        if let warning = appState.hotkeyWarning {
            let warningItem = NSMenuItem(
                title: localized("Warning", "警告") + ": \(warning)",
                action: nil,
                keyEquivalent: ""
            )
            warningItem.isEnabled = false
            menu.addItem(warningItem)
        }

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: localized("Quit", "終了"), action: #selector(didTapQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makeModeMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: localized("Modes", "モード"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for mode in appState.preferences.transformModes {
            let title = mode.isEnabled
                ? mode.displayName
                : "\(mode.displayName) (\(localized("Disabled", "無効")))"
            let item = NSMenuItem(title: title, action: #selector(didSelectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.id.uuidString
            item.state = appState.activeMode.id == mode.id ? .on : .off
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
            "\(localized("Status", "状態")): \(transformPhaseName(appState.transformPhase))",
            "\(localized("Mode", "モード")): \(appState.activeMode.displayName)",
            "\(localized("Model", "モデル")): \(appState.activeMode.model)"
        ]
        if let warning = appState.hotkeyWarning {
            lines.append("\(localized("Warning", "警告")): \(warning)")
        }
        return lines.joined(separator: "\n")
    }

    private func transformPhaseName(_ phase: TransformPhase) -> String {
        switch phase {
        case .idle:
            return localized("Idle", "待機中")
        case .capturingInput:
            return localized("Capturing text", "テキスト取得中")
        case .awaitingModelResponse:
            return localized("Waiting for AI response", "AI応答待ち")
        case .applyingOutput:
            return localized("Applying result", "結果反映中")
        }
    }

    private func localized(_ english: String, _ japanese: String) -> String {
        appState.preferences.interfaceLanguage == .japanese ? japanese : english
    }

    @objc private func didTapStatusButton(_ sender: NSStatusBarButton) {
        statusItem.popUpMenu(buildMenu())
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
            let id = UUID(uuidString: raw)
        else { return }
        appState.selectMode(id)
    }
}
