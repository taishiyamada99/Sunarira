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

    func testLegacyTransformHotkeyMigratesToMode1() throws {
        let json = """
        {
          "schemaVersion": 2,
          "hotkeys": {
            "transform": { "keyCode": 18, "modifiers": 4096 },
            "cycleMode": { "keyCode": 46, "modifiers": 4096 }
          }
        }
        """
        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.hotkeys[.mode1]?.keyCode, 18)
        XCTAssertEqual(decoded.hotkeys[.mode1]?.modifiers, 4096)
        XCTAssertEqual(decoded.hotkeys[.mode2], AppPreferences.default.hotkeys[.mode2])
    }

    func testSanitizeEnsuresAtLeastOneEnabledMode() {
        var prefs = AppPreferences.default
        for index in prefs.transformModes.indices {
            prefs.transformModes[index].isEnabled = false
        }

        prefs.sanitize()

        XCTAssertTrue(prefs.transformModes.contains(where: \.isEnabled))
        XCTAssertTrue(prefs.transformModes[0].isEnabled)
    }

    func testSanitizeActiveModeFallsBackToEnabledMode() {
        var prefs = AppPreferences.default
        guard prefs.transformModes.count >= 2 else {
            XCTFail("Expected at least 2 default modes")
            return
        }
        prefs.transformModes[0].isEnabled = false
        prefs.transformModes[1].isEnabled = true
        prefs.activeModeID = prefs.transformModes[0].id

        prefs.sanitize()

        XCTAssertEqual(prefs.activeModeID, prefs.transformModes[1].id)
    }

    func testLaunchAtLoginDefaultsToFalseWhenKeyIsMissing() throws {
        let json = """
        {
          "schemaVersion": 2
        }
        """

        let decoded = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.launchAtLogin)
    }
}
