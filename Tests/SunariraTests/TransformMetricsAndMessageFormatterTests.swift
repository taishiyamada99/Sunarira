import XCTest
@testable import Sunarira

final class TransformMetricsAndMessageFormatterTests: XCTestCase {
    func testTransformMetricsCompressionPercentUsesFloor() {
        let metrics = TransformMetrics(
            sourceText: String(repeating: "a", count: 100),
            resultText: String(repeating: "b", count: 80),
            elapsedMilliseconds: 1_200
        )
        XCTAssertEqual(metrics.sourceCount, 100)
        XCTAssertEqual(metrics.resultCount, 80)
        XCTAssertEqual(metrics.compressionPercent, 80)
        XCTAssertEqual(metrics.elapsedSecondsOneDecimal, "1.2")
    }

    func testTransformMetricsCanExceedHundredPercent() {
        let metrics = TransformMetrics(
            sourceText: String(repeating: "a", count: 100),
            resultText: String(repeating: "b", count: 101),
            elapsedMilliseconds: 120
        )
        XCTAssertEqual(metrics.compressionPercent, 101)
    }

    func testTransformMetricsFloorsFractionalPercent() {
        let metrics = TransformMetrics(sourceText: "abc", resultText: "ab", elapsedMilliseconds: 350)
        XCTAssertEqual(metrics.compressionPercent, 66)
    }

    func testTransformMetricsZeroSourceDefaultsToZeroPercent() {
        let metrics = TransformMetrics(sourceText: "", resultText: "abc", elapsedMilliseconds: 10)
        XCTAssertEqual(metrics.compressionPercent, 0)
    }

    func testTransformMetricsRoundsElapsedToOneDecimalSecond() {
        let metrics = TransformMetrics(sourceText: "abc", resultText: "ab", elapsedMilliseconds: 1_260)
        XCTAssertEqual(metrics.elapsedSecondsOneDecimal, "1.3")
    }

    func testFormatterUsesOneLineJapaneseMessage() {
        let formatter = TransformResultMessageFormatter()
        let metrics = TransformMetrics(
            sourceText: String(repeating: "あ", count: 100),
            resultText: String(repeating: "い", count: 80),
            elapsedMilliseconds: 1_240
        )
        XCTAssertEqual(formatter.message(for: metrics, language: .japanese), "100→80文字(80%,1.2秒)")
    }

    func testFormatterUsesOneLineEnglishMessage() {
        let formatter = TransformResultMessageFormatter()
        let metrics = TransformMetrics(
            sourceText: String(repeating: "a", count: 100),
            resultText: String(repeating: "b", count: 80),
            elapsedMilliseconds: 1_240
        )
        XCTAssertEqual(formatter.message(for: metrics, language: .english), "100→80 chars (80%, 1.2s)")
    }

    func testFormatterSupportsGermanSpanishFrench() {
        let formatter = TransformResultMessageFormatter()
        let metrics = TransformMetrics(
            sourceText: String(repeating: "a", count: 100),
            resultText: String(repeating: "b", count: 80),
            elapsedMilliseconds: 1_240
        )

        XCTAssertEqual(formatter.message(for: metrics, language: .german), "100→80 Zeichen (80%, 1.2s)")
        XCTAssertEqual(formatter.message(for: metrics, language: .spanish), "100→80 caracteres (80%, 1.2s)")
        XCTAssertEqual(formatter.message(for: metrics, language: .french), "100→80 caractères (80%, 1.2s)")
    }
}
