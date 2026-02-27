import Foundation

struct TransformRequestPayload: Equatable {
    let model: String
    let prompt: String
}

protocol TransformEngine {
    func transform(request: TransformRequestPayload) async throws -> String
}

enum TransformEngineError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Endpoint URL is invalid."
        case .invalidResponse:
            return "Invalid response from transform endpoint."
        case let .rpcError(message):
            return "Transform endpoint error: \(message)"
        }
    }
}
