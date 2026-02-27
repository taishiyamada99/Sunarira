import Foundation

@MainActor
final class TransformService {
    private let promptBuilder: PromptBuilder
    private let engineProvider: () -> TransformEngine

    init(
        promptBuilder: PromptBuilder = PromptBuilder(),
        engineProvider: @escaping () -> TransformEngine
    ) {
        self.promptBuilder = promptBuilder
        self.engineProvider = engineProvider
    }

    func transform(input: String, context: TransformContext) async throws -> String {
        guard !input.isEmpty else { return input }

        AppLogger.payload("Transform input", text: input)
        let request = promptBuilder.makeRequest(input: input, context: context)
        AppLogger.info(
            "Transform request built. mode=\"\(context.modeDisplayName)\", model=\(context.model)"
        )
        let requestStart = DispatchTime.now().uptimeNanoseconds
        let engineOutput: String
        do {
            engineOutput = try await engineProvider().transform(request: request)
        } catch {
            let elapsedMs = elapsedMilliseconds(sinceUptimeNanoseconds: requestStart)
            AppLogger.warning(
                "Transform completed. latencyMs=\(elapsedMs) result=failure mode=\"\(context.modeDisplayName)\" model=\(context.model) error=\(error.localizedDescription)"
            )
            throw error
        }
        let elapsedMs = elapsedMilliseconds(sinceUptimeNanoseconds: requestStart)
        AppLogger.info(
            "Transform completed. latencyMs=\(elapsedMs) result=success mode=\"\(context.modeDisplayName)\" model=\(context.model)"
        )
        AppLogger.payload("Transform output (engine)", text: engineOutput)
        let normalized = normalize(engineOutput)
        AppLogger.payload("Transform output (final)", text: normalized)
        return normalized
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func elapsedMilliseconds(sinceUptimeNanoseconds start: UInt64) -> Int {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= start else { return 0 }
        return Int((now - start) / 1_000_000)
    }
}
