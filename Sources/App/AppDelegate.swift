import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var hotkeyManager: HotkeyManager?
    private var appCoordinator: AppCoordinator?
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?

    private var accessibilityService = AccessibilityService()
    private var notifier = UserNotifier()
    private var clipboardService = ClipboardService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isRunningTests {
            return
        }

        NSApp.setActivationPolicy(.accessory)

        let appState = AppState()
        let hotkeyManager = HotkeyManager()

        let axTextService = AXTextService(
            accessibilityService: accessibilityService,
            clipboardService: clipboardService
        )

        let clipboardFallbackService = ClipboardFallbackService(clipboardService: clipboardService)

        let transformService = TransformService { [weak appState] in
            guard let appState else { return LocalStubEngine() }
            return Self.makeEngine(for: appState.preferences)
        }

        let transformResultNotifier = TransformResultNotifier(
            inAppToastPresenter: InAppToastPresenter(),
            languageProvider: { [weak appState] in
                appState?.preferences.interfaceLanguage ?? .english
            }
        )

        let coordinator = AppCoordinator(
            appState: appState,
            hotkeyManager: hotkeyManager,
            accessibilityService: accessibilityService,
            notifier: notifier,
            axTextService: axTextService,
            clipboardFallbackService: clipboardFallbackService,
            transformService: transformService,
            transformResultNotifier: transformResultNotifier
        )

        let settingsWindowController = SettingsWindowController(
            appState: appState,
            accessibilityService: accessibilityService,
            onReRegisterHotkeys: {
                coordinator.registerHotkeys()
            }
        )

        let statusItemController = StatusItemController(
            appState: appState,
            accessibilityService: accessibilityService,
            onTransform: {
                coordinator.triggerTransform()
            },
            onOpenSettings: {
                settingsWindowController.show()
            },
            onReRegisterHotkeys: {
                coordinator.registerHotkeys()
            }
        )

        self.appState = appState
        self.hotkeyManager = hotkeyManager
        appCoordinator = coordinator
        self.settingsWindowController = settingsWindowController
        self.statusItemController = statusItemController

        coordinator.start()
        Task {
            await appState.refreshAvailableModels()
        }

        if !accessibilityService.isTrusted(promptIfNeeded: false) {
            notifier.notify(
                title: appState.preferences.interfaceLanguage.localized(
                    english: "Accessibility permission needed",
                    japanese: "アクセシビリティ許可が必要です",
                    german: "Bedienungshilfen-Berechtigung erforderlich",
                    spanish: "Se requiere permiso de Accesibilidad",
                    french: "Autorisation Accessibilité requise"
                ),
                message: appState.preferences.interfaceLanguage.localized(
                    english: "Grant Accessibility permission for direct in-place replace.",
                    japanese: "その場置換にはアクセシビリティ許可が必要です。",
                    german: "Erteilen Sie die Bedienungshilfen-Berechtigung für direktes Ersetzen.",
                    spanish: "Concede permiso de Accesibilidad para reemplazo directo en el lugar.",
                    french: "Accordez l'autorisation Accessibilité pour le remplacement direct sur place."
                )
            )
        }
    }

    static func makeEngine(for preferences: AppPreferences) -> TransformEngine {
        CodexAppServerStdioEngine(launchCommand: preferences.stdioCommand)
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
