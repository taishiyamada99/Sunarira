import XCTest
@testable import Sunarira

final class AppStateCycleAndLocalizationTests: XCTestCase {
    @MainActor
    func testCycleModeMovesAcrossEnabledModes() {
        let defaults = isolatedDefaults("cycle")
        let appState = AppState(
            defaults: defaults,
            modelCatalogService: DummyModelCatalogService()
        )

        let first = appState.activeMode.id
        appState.cycleMode()
        let second = appState.activeMode.id
        XCTAssertNotEqual(first, second)

        // Disable current and ensure cycle still works on enabled set.
        appState.updateMode(id: second) { $0.isEnabled = false }
        appState.cycleMode()
        XCTAssertNotEqual(appState.activeMode.id, second)
    }

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
