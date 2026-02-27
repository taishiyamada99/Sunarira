import XCTest
@testable import Sunarira

final class AppStateCycleAndLocalizationTests: XCTestCase {
    @MainActor
    func testLocalizationAppliesToModelRefreshErrorMessage() async {
        let defaults = isolatedDefaults("localize")
        let appState = AppState(
            defaults: defaults,
            modelCatalogService: DummyModelCatalogService()
        )
        appState.updatePreferences { prefs in
            prefs.interfaceLanguage = .japanese
        }

        await appState.refreshAvailableModels()
        XCTAssertEqual(appState.modelRefreshMessage, "model/list から 1 件のモデルを読み込みました。")
    }

    @MainActor
    func testRegisteredHotkeysMatchConfiguredModes() {
        let defaults = isolatedDefaults("hotkey-map")
        let appState = AppState(
            defaults: defaults,
            modelCatalogService: DummyModelCatalogService()
        )

        appState.updatePreferences { prefs in
            prefs.transformModes = Array(prefs.transformModes.prefix(2))
        }

        let registered = appState.registeredHotkeys()
        XCTAssertEqual(registered.count, 2)
        XCTAssertNotNil(registered[.mode1])
        XCTAssertNotNil(registered[.mode2])
        XCTAssertNil(registered[.mode3])
        XCTAssertEqual(appState.modeForHotkeyAction(.mode2)?.id, appState.preferences.transformModes[1].id)
    }

    @MainActor
    func testRegisteredHotkeysExcludeDisabledModes() {
        let defaults = isolatedDefaults("hotkey-disabled")
        let appState = AppState(
            defaults: defaults,
            modelCatalogService: DummyModelCatalogService()
        )

        guard appState.preferences.transformModes.count >= 2 else {
            XCTFail("Expected at least 2 default modes")
            return
        }
        let secondID = appState.preferences.transformModes[1].id
        appState.updateMode(id: secondID) { $0.isEnabled = false }

        let registered = appState.registeredHotkeys()
        XCTAssertNotNil(registered[.mode1])
        XCTAssertNil(registered[.mode2])
    }

    @MainActor
    func testSelectModeIgnoresDisabledMode() {
        let defaults = isolatedDefaults("select-disabled")
        let appState = AppState(
            defaults: defaults,
            modelCatalogService: DummyModelCatalogService()
        )

        guard appState.preferences.transformModes.count >= 2 else {
            XCTFail("Expected at least 2 default modes")
            return
        }

        let originalActive = appState.activeMode.id
        let disabledModeID = appState.preferences.transformModes[1].id
        appState.updateMode(id: disabledModeID) { $0.isEnabled = false }
        appState.selectMode(disabledModeID)

        XCTAssertEqual(appState.activeMode.id, originalActive)
    }

    @MainActor
    func testRemoveModeKeepsEnabledActiveMode() {
        let defaults = isolatedDefaults("remove-mode-enabled")
        let appState = AppState(
            defaults: defaults,
            modelCatalogService: DummyModelCatalogService()
        )

        // Make first mode disabled and second mode active/enabled.
        let firstID = appState.preferences.transformModes[0].id
        let secondID = appState.preferences.transformModes[1].id
        appState.selectMode(secondID)
        appState.updateMode(id: firstID) { $0.isEnabled = false }
        appState.removeMode(id: secondID)

        XCTAssertTrue(appState.activeMode.isEnabled)
        XCTAssertTrue(appState.preferences.transformModes.contains(where: \.isEnabled))
    }

    private func isolatedDefaults(_ suffix: String) -> UserDefaults {
        let suiteName = "AppStateCycleAndLocalizationTests.\(suffix).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct DummyModelCatalogService: ModelCatalogServiceProtocol {
    func fetchModels(stdioCommand _: String) async throws -> [String] {
        ["gpt-5.2"]
    }
}
