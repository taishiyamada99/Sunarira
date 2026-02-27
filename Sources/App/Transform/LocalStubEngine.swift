import Foundation

struct LocalStubEngine: TransformEngine {
    func transform(request: TransformRequestPayload) async throws -> String {
        let prompt = request.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return "" }

        // Deterministic fallback used only in tests.
        return prompt
    }
}
