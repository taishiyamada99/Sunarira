import XCTest
@testable import Sunarira

final class AppPreferencesModeTests: XCTestCase {
    func testDecodeLegacyPreferencesResetsToDefault() throws {
        let legacyJSON = """
        {
          "interfaceLanguage": "japanese",
          "structureMode": "clean"
        }
        """
        let data = Data(legacyJSON.utf8)
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, AppPreferences.schemaVersionCurrent)
        XCTAssertEqual(decoded.transformModes.count, 3)
        XCTAssertEqual(decoded.interfaceLanguage, .english)
    }

    func testModeCountIsClampedToOneToFive() {
        var prefs = AppPreferences.default
        prefs.transformModes = []
        prefs.sanitize()
        XCTAssertEqual(prefs.transformModes.count, 1)

        prefs.transformModes = (0 ..< 10).map { index in
            TransformModePreset(
                displayName: "Mode \(index)",
                promptTemplate: "Prompt \(index)",
                model: "gpt-5.2"
            )
        }
        prefs.sanitize()
        XCTAssertEqual(prefs.transformModes.count, 5)
    }
}
