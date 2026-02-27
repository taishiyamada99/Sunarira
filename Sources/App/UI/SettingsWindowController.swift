import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let appState: AppState
    private let accessibilityService: AccessibilityService
    private let onReRegisterHotkeys: () -> Void

    private var window: NSWindow?

    init(
        appState: AppState,
        accessibilityService: AccessibilityService,
        onReRegisterHotkeys: @escaping () -> Void
    ) {
        self.appState = appState
        self.accessibilityService = accessibilityService
        self.onReRegisterHotkeys = onReRegisterHotkeys
        super.init()
    }

    func show() {
        if window == nil {
            let rootView = SettingsView(
                appState: appState,
                accessibilityService: accessibilityService,
                onReRegisterHotkeys: onReRegisterHotkeys
            )
            let hosting = NSHostingController(rootView: rootView)

            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = windowTitle()
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 680, height: 800))
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            window = newWindow
        }

        window?.title = windowTitle()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appState.refreshLaunchAtLoginState()
        appState.refreshAccessibilityTrustStatus()
    }

    private func windowTitle() -> String {
        appState.preferences.interfaceLanguage.localized(
            english: "Sunarira Settings",
            japanese: "スナリラ (Sunarira) 設定",
            german: "Sunarira Einstellungen",
            spanish: "Configuración de Sunarira",
            french: "Réglages de Sunarira"
        )
    }

    func windowDidBecomeKey(_: Notification) {
        appState.setRuntimeLogStreamingEnabled(true)
        appState.refreshAccessibilityTrustStatus()
        appState.startAccessibilityStatusPolling()
    }

    func windowDidResignKey(_: Notification) {
        appState.stopAccessibilityStatusPolling()
        appState.setRuntimeLogStreamingEnabled(false)
    }

    func windowWillClose(_: Notification) {
        appState.stopAccessibilityStatusPolling()
        appState.setRuntimeLogStreamingEnabled(false)
        window = nil
    }
}
