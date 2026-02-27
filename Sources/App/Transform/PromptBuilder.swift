import Foundation

struct PromptBuilder {
    func makeRequest(input: String, context: TransformContext) -> TransformRequestPayload {
        TransformRequestPayload(
            model: context.model,
            prompt: buildPrompt(input: input, context: context)
        )
    }

    func buildPrompt(input: String, context: TransformContext) -> String {
        let trimmedTemplate = context.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTemplate = trimmedTemplate.isEmpty
            ? "Rewrite the input text to be clearer while preserving meaning."
            : trimmedTemplate

        return """
        \(effectiveTemplate)

        Input:
        \(input)
        """
    }
}
