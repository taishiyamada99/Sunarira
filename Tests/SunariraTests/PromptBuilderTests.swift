import XCTest
@testable import Sunarira

final class PromptBuilderTests: XCTestCase {
    func testPromptContainsTemplateAndInputOnly() {
        let modeID = UUID()
        let context = TransformContext(
            modeID: modeID,
            modeDisplayName: "超端的",
            promptTemplate: "Summarize very briefly.",
            model: "gpt-5.2",
            inputText: "テスト入力"
        )

        let prompt = PromptBuilder().buildPrompt(input: "テスト入力", context: context)

        XCTAssertTrue(prompt.contains("Summarize very briefly."))
        XCTAssertTrue(prompt.contains("Input:"))
        XCTAssertTrue(prompt.contains("テスト入力"))
        XCTAssertFalse(prompt.contains("Mode name:"))
        XCTAssertFalse(prompt.contains("<<<"))
    }

    func testEmptyTemplateFallsBackToDefaultInstruction() {
        let context = TransformContext(
            modeID: UUID(),
            modeDisplayName: "General",
            promptTemplate: "   ",
            model: "gpt-5.2",
            inputText: "sample"
        )

        let prompt = PromptBuilder().buildPrompt(input: "sample", context: context)
        XCTAssertTrue(prompt.contains("Rewrite the input text to be clearer while preserving meaning."))
    }

    func testMakeRequestUsesContextModel() {
        let context = TransformContext(
            modeID: UUID(),
            modeDisplayName: "General",
            promptTemplate: "Keep intent.",
            model: "spark",
            inputText: "sample"
        )

        let request = PromptBuilder().makeRequest(input: "sample", context: context)
        XCTAssertEqual(request.model, "spark")
        XCTAssertTrue(request.prompt.contains("Keep intent."))
    }
}
