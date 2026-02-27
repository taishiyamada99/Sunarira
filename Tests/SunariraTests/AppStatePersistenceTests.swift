import XCTest
@testable import Sunarira

final class AppStatePersistenceTests: XCTestCase {
    @MainActor
    func testPreferencesPersistAcrossInstances() {
        let suiteName = "AppStatePersistenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState1 = AppState(defaults: defaults, modelCatalogService: PersistMockModelCatalogService())
        let originalFirstID = appState1.preferences.transformModes[0].id
        appState1.updateMode(id: originalFirstID) { mode in
            mode.displayName = "My Mode"
            mode.model = "spark"
        }
        appState1.selectMode(originalFirstID)

        let appState2 = AppState(defaults: defaults, modelCatalogService: PersistMockModelCatalogService())
        XCTAssertEqual(appState2.activeMode.id, originalFirstID)
        XCTAssertEqual(appState2.activeMode.displayName, "My Mode")
        XCTAssertEqual(appState2.activeMode.model, "spark")
    }
}

private struct PersistMockModelCatalogService: ModelCatalogServiceProtocol {
    func fetchModels(stdioCommand _: String) async throws -> [String] {
        ["gpt-5.2", "spark"]
    }
}
