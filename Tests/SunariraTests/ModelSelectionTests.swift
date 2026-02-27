import XCTest
@testable import Sunarira

final class ModelSelectionTests: XCTestCase {
    @MainActor
    func testDefaultModelIsGPT52() {
        XCTAssertEqual(AppPreferences.default.transformModes.first?.model, "gpt-5.2")
        XCTAssertEqual(AppPreferences.default.interfaceLanguage, .english)
    }

    @MainActor
    func testRefreshAvailableModelsLoadsFromModelList() async {
        let defaults = makeIsolatedDefaults()
        let appState = AppState(
            defaults: defaults,
            modelCatalogService: MockModelCatalogService(
                result: .success(["gpt-5.2", "spark", "gpt-5.3"])
            )
        )

        await appState.refreshAvailableModels()

        XCTAssertEqual(appState.availableModels.first, "gpt-5.3")
        XCTAssertTrue(appState.modelOptions().contains("spark"))
        XCTAssertTrue(appState.modelRefreshMessage?.contains("Loaded 3") == true)
    }

    @MainActor
    func testResolveModelFallsBackWhenSelectedModelIsUnavailable() {
        let defaults = makeIsolatedDefaults()
        let appState = AppState(
            defaults: defaults,
            modelCatalogService: MockModelCatalogService(result: .success(["gpt-5.2", "spark"]))
        )

        appState.availableModels = ["gpt-5.2", "spark"]
        appState.updatePreferences { preferences in
            preferences.transformModes[0].model = "gpt-unknown"
        }

        let resolved = appState.resolveModel(for: appState.activeMode)
        XCTAssertEqual(resolved.resolved, "gpt-5.2")
        XCTAssertEqual(resolved.fallbackFrom, "gpt-unknown")
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "ModelSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private struct MockModelCatalogService: ModelCatalogServiceProtocol {
    let result: Result<[String], Error>

    func fetchModels(stdioCommand _: String) async throws -> [String] {
        switch result {
        case .success(let models):
            return models
        case .failure(let error):
            throw error
        }
    }
}
