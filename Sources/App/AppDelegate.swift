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

        let coordinator = AppCoordinator(
            appState: appState,
            hotkeyManager: hotkeyManager,
            accessibilityService: accessibilityService,
            notifier: notifier,
            axTextService: axTextService,
            clipboardFallbackService: clipboardFallbackService,
            transformService: transformService
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
                title: "Accessibility permission needed",
                message: "Grant Accessibility permission for direct in-place replace."
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
