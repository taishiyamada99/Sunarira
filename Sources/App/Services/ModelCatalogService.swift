import Foundation

protocol ModelCatalogServiceProtocol: Sendable {
    func fetchModels(stdioCommand: String) async throws -> [String]
}

enum ModelCatalogError: LocalizedError {
    case invalidStdioCommand
    case modelListUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidStdioCommand:
            return "Stdio launch command is empty."
        case .modelListUnavailable:
            return "model/list did not return any model identifiers."
        }
    }
}

struct ModelCatalogService: ModelCatalogServiceProtocol {
    func fetchModels(stdioCommand: String) async throws -> [String] {
        let command = stdioCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw ModelCatalogError.invalidStdioCommand
        }

        let client = StdioJSONRPCClient(launchCommand: command, timeout: 20)
        var allModels: [String] = []
        var cursor: String?
        var pageCount = 0

        repeat {
            pageCount += 1
            let result = try await client.request(
                method: "model/list",
                params: ModelListParams(
                    cursor: cursor,
                    includeHidden: true,
                    limit: 100
                ),
                initializeFirst: true
            )

            let page = extractModelPage(from: result)
            allModels.append(contentsOf: page.models)
            cursor = normalizedCursor(page.nextCursor)
        } while pageCount < 50 && cursor != nil

        let models = allModels
        guard !models.isEmpty else {
            throw ModelCatalogError.modelListUnavailable
        }

        return normalizedModels(models)
    }

    private func extractModelPage(from value: Any) -> ModelListPage {
        if let strings = value as? [String] {
            return ModelListPage(models: strings, nextCursor: nil)
        }

        if let list = value as? [Any] {
            return ModelListPage(models: list.compactMap(extractModelID(from:)), nextCursor: nil)
        }

        if let object = value as? [String: Any] {
            let nextCursor = extractNextCursor(from: object)
            if let data = object["data"] as? [Any] {
                return ModelListPage(models: data.compactMap(extractModelID(from:)), nextCursor: nextCursor)
            }
            if let items = object["items"] as? [Any] {
                return ModelListPage(models: items.compactMap(extractModelID(from:)), nextCursor: nextCursor)
            }
            return ModelListPage(models: [], nextCursor: nextCursor)
        }

        return ModelListPage(models: [], nextCursor: nil)
    }

    private func extractNextCursor(from object: [String: Any]) -> String? {
        if let cursor = object["nextCursor"] as? String {
            return cursor
        }
        if let cursor = object["next_cursor"] as? String {
            return cursor
        }
        if
            let pagination = object["pagination"] as? [String: Any],
            let cursor = pagination["nextCursor"] as? String
        {
            return cursor
        }
        return nil
    }

    private func normalizedCursor(_ cursor: String?) -> String? {
        guard let cursor else { return nil }
        let trimmed = cursor.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func extractModelID(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        guard let object = value as? [String: Any] else {
            return nil
        }

        if let model = object["model"] as? String {
            return model
        }
        if let id = object["id"] as? String {
            return id
        }

        return nil
    }

    private func normalizedModels(_ models: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for model in models.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !model.isEmpty {
            if !seen.contains(model) {
                normalized.append(model)
                seen.insert(model)
            }
        }

        return normalized
    }
}

private struct ModelListPage {
    let models: [String]
    let nextCursor: String?
}

private struct ModelListParams: Encodable, Sendable {
    let cursor: String?
    let includeHidden: Bool?
    let limit: UInt32?
}
