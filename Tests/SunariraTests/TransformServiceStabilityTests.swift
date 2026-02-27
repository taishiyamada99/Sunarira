import XCTest
@testable import Sunarira

final class TransformServiceStabilityTests: XCTestCase {
    @MainActor
    func testTransformServiceStabilityOverHundredRuns() async throws {
        let service = TransformService(engineProvider: { StableMockEngine() })
        let mode = AppPreferences.default.transformModes[0]

        for index in 0 ..< 120 {
            let input = "会議メモ\(index)。背景と課題を整理し、次アクションを決める。"
            let context = TransformContext(
                modeID: mode.id,
                modeDisplayName: mode.displayName,
                promptTemplate: mode.promptTemplate,
                model: mode.model,
                inputText: input
            )

            let output = try await service.transform(input: input, context: context)
            XCTAssertFalse(output.isEmpty)
        }
    }

    @MainActor
    func testTransformLatencyIsLoggedInMillisecondsOnSuccess() async throws {
        AppLogger.clear()
        let service = TransformService(
            engineProvider: {
                DelayedMockEngine(delayMs: 120, result: .success("OK"))
            }
        )
        let mode = AppPreferences.default.transformModes[0]
        let context = TransformContext(
            modeID: mode.id,
            modeDisplayName: mode.displayName,
            promptTemplate: mode.promptTemplate,
            model: mode.model,
            inputText: "長めの日本語テキストをここに入れて、計測ログを検証します。"
        )

        _ = try await service.transform(input: context.inputText, context: context)

        let entries = AppLogger.recentEntries(limit: 100)
        let latencyLine = entries.last { $0.contains("Transform completed.") && $0.contains("result=success") }
        XCTAssertNotNil(latencyLine)
        XCTAssertTrue(latencyLine?.contains("latencyMs=") == true)
        let latencyMs = extractLatencyMs(from: latencyLine)
        XCTAssertNotNil(latencyMs)
        XCTAssertGreaterThanOrEqual(latencyMs ?? 0, 100)
    }

    @MainActor
    func testTransformLatencyIsLoggedInMillisecondsOnFailure() async {
        AppLogger.clear()
        let service = TransformService(
            engineProvider: {
                DelayedMockEngine(delayMs: 60, result: .failure(DelayedMockEngineError.failed))
            }
        )
        let mode = AppPreferences.default.transformModes[0]
        let context = TransformContext(
            modeID: mode.id,
            modeDisplayName: mode.displayName,
            promptTemplate: mode.promptTemplate,
            model: mode.model,
            inputText: "失敗時ログも確認します。"
        )

        do {
            _ = try await service.transform(input: context.inputText, context: context)
            XCTFail("Expected transform to fail")
        } catch {
            // expected
        }

        let entries = AppLogger.recentEntries(limit: 100)
        let latencyLine = entries.last { $0.contains("Transform completed.") && $0.contains("result=failure") }
        XCTAssertNotNil(latencyLine)
        XCTAssertTrue(latencyLine?.contains("latencyMs=") == true)
        let latencyMs = extractLatencyMs(from: latencyLine)
        XCTAssertNotNil(latencyMs)
        XCTAssertGreaterThanOrEqual(latencyMs ?? 0, 50)
    }

    func testStdioEngineTransformsSuccessfullyWithThreadTurnProtocol() async throws {
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scriptURL = try makeMockStdioServerScript(logURL: logURL)
        let engine = CodexAppServerStdioEngine(launchCommand: scriptURL.path, timeout: 15)
        let request = TransformRequestPayload(
            model: "gpt-5.2",
            prompt: "Rewrite this."
        )

        let output = try await engine.transform(request: request)
        XCTAssertEqual(output, "STDIO_TRANSFORM_OK")

        let logs = try String(contentsOf: logURL, encoding: .utf8)
        let methods = extractRequestMethods(from: logs)
        XCTAssertTrue(methods.contains("thread/start"))
        XCTAssertTrue(methods.contains("turn/start"))
        XCTAssertTrue(methods.contains("thread/read"))
        XCTAssertFalse(methods.contains("newConversation"))
        XCTAssertFalse(methods.contains("sendUserTurn"))
    }

    func testSelectedModelIsSentInThreadStartAndTurnStartParams() async throws {
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scriptURL = try makeMockStdioServerScript(logURL: logURL)
        let engine = CodexAppServerStdioEngine(launchCommand: scriptURL.path, timeout: 15)
        let request = TransformRequestPayload(
            model: "spark",
            prompt: "Rewrite this."
        )

        _ = try await engine.transform(request: request)

        let logs = try String(contentsOf: logURL, encoding: .utf8)
        let requests = extractRequestObjects(from: logs)

        let threadStartModel = extractModelParam(method: "thread/start", from: requests)
        let turnStartModel = extractModelParam(method: "turn/start", from: requests)

        XCTAssertEqual(threadStartModel, "spark")
        XCTAssertEqual(turnStartModel, "spark")
    }

    func testModelCatalogFetchesFromModelListOnly() async throws {
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scriptURL = try makeMockStdioServerScript(logURL: logURL)
        let service = ModelCatalogService()

        let models = try await service.fetchModels(stdioCommand: scriptURL.path)
        XCTAssertEqual(models, ["gpt-5.2", "spark"])

        let logs = try String(contentsOf: logURL, encoding: .utf8)
        let methods = extractRequestMethods(from: logs)
        XCTAssertTrue(methods.contains("initialize"))
        XCTAssertTrue(methods.contains("initialized"))
        XCTAssertTrue(methods.contains("model/list"))
        XCTAssertFalse(methods.contains("listModels"))
        XCTAssertFalse(methods.contains("models.list"))
        XCTAssertFalse(methods.contains("models"))
    }

    func testModelCatalogIncludesHiddenModelsAndFollowsNextCursor() async throws {
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scriptURL = try makePaginatedModelListScript(logURL: logURL)
        let service = ModelCatalogService()

        let models = try await service.fetchModels(stdioCommand: scriptURL.path)
        XCTAssertEqual(models, ["gpt-5.2", "codex-spark"])

        let logs = try String(contentsOf: logURL, encoding: .utf8)
        let requests = extractRequestObjects(from: logs)
        let modelListRequests = requests.filter { $0["method"] as? String == "model/list" }
        XCTAssertFalse(modelListRequests.isEmpty)
        let params = modelListRequests.last?["params"] as? [String: Any]
        XCTAssertEqual(params?["includeHidden"] as? Bool, true)
        XCTAssertEqual((params?["limit"] as? NSNumber)?.intValue, 100)
    }

    func testModelCatalogReturnsWithoutWaitingForProcessExit() async throws {
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scriptURL = try makeLongRunningModelListScript(logURL: logURL)
        let service = ModelCatalogService()

        let start = Date()
        let models = try await service.fetchModels(stdioCommand: scriptURL.path)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(models, ["gpt-5.2", "codex-spark"])
        XCTAssertLessThan(elapsed, 4.0, "model/list should return before server process exits")
    }

    private func makeMockStdioServerScript(logURL: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let scriptURL = directory.appendingPathComponent("mock_stdio_server.sh")
        let script = """
        #!/bin/zsh
        log_file="\(logURL.path)"
        if [[ ! -f "$log_file" ]]; then
          : > "$log_file"
        fi

        while IFS= read -r line; do
          printf '%s\n' "$line" >> "$log_file"

          id=$(/usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("id",""))' "$line" 2>/dev/null)
          method=$(/usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("method",""))' "$line" 2>/dev/null)
          if [[ -z "$id" ]]; then
            id="fallback-id"
          fi

          if [[ "$method" == "initialize" ]]; then
            printf '{"jsonrpc":"2.0","id":"%s","result":{"status":"ok"}}\\n' "$id"
          elif [[ "$method" == "model/list" ]]; then
            printf '{"jsonrpc":"2.0","id":"%s","result":{"data":[{"model":"gpt-5.2"},{"model":"spark"}]}}\\n' "$id"
            break
          elif [[ "$method" == "thread/start" ]]; then
            printf '{"jsonrpc":"2.0","id":"%s","result":{"thread":{"id":"thread-1"}}}\\n' "$id"
          elif [[ "$method" == "turn/start" ]]; then
            printf '{"jsonrpc":"2.0","id":"%s","result":{"turn":{"id":"turn-1","status":"inProgress"}}}\\n' "$id"
            printf '{"method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1"}}}\\n'
            printf '{"method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","delta":"STDIO_TRANSFORM_OK"}}\\n'
            printf '{"method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}\\n'
          elif [[ "$method" == "thread/read" ]]; then
            printf '{"jsonrpc":"2.0","id":"%s","result":{"thread":{"id":"thread-1","turns":[{"id":"turn-1","items":[{"type":"assistant_message","content":[{"type":"output_text","text":"STDIO_TRANSFORM_OK"}]}]}]}}}\\n' "$id"
            break
          fi
        done
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func makePaginatedModelListScript(logURL: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let scriptURL = directory.appendingPathComponent("mock_paginated_model_list.sh")
        let script = """
        #!/bin/zsh
        log_file="\(logURL.path)"
        : > "$log_file"

        while IFS= read -r line; do
          printf '%s\n' "$line" >> "$log_file"

          id=$(/usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("id",""))' "$line" 2>/dev/null)
          method=$(/usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("method",""))' "$line" 2>/dev/null)
          cursor=$(/usr/bin/python3 -c 'import json,sys; p=json.loads(sys.argv[1]).get("params",{}); c=p.get("cursor", None); print("" if c is None else c)' "$line" 2>/dev/null)

          if [[ "$method" == "initialize" ]]; then
            printf '{"jsonrpc":"2.0","id":"%s","result":{"status":"ok"}}\\n' "$id"
          elif [[ "$method" == "model/list" ]]; then
            if [[ -z "$cursor" ]]; then
              printf '{"jsonrpc":"2.0","id":"%s","result":{"data":[{"model":"gpt-5.2"}],"nextCursor":"page-2"}}\\n' "$id"
            elif [[ "$cursor" == "page-2" ]]; then
              printf '{"jsonrpc":"2.0","id":"%s","result":{"data":[{"model":"codex-spark"}],"nextCursor":null}}\\n' "$id"
              break
            else
              printf '{"jsonrpc":"2.0","id":"%s","result":{"data":[],"nextCursor":null}}\\n' "$id"
              break
            fi
          fi
        done
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func makeLongRunningModelListScript(logURL: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let scriptURL = directory.appendingPathComponent("mock_long_running_model_list.sh")
        let script = """
        #!/bin/zsh
        log_file="\(logURL.path)"
        : > "$log_file"

        while IFS= read -r line; do
          printf '%s\n' "$line" >> "$log_file"

          id=$(/usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("id",""))' "$line" 2>/dev/null)
          method=$(/usr/bin/python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("method",""))' "$line" 2>/dev/null)

          if [[ "$method" == "initialize" ]]; then
            printf '{"jsonrpc":"2.0","id":"%s","result":{"status":"ok"}}\\n' "$id"
          elif [[ "$method" == "model/list" ]]; then
            printf '{"jsonrpc":"2.0","id":"%s","result":{"data":[{"model":"gpt-5.2"},{"model":"codex-spark"}]}}\\n' "$id"
            # Keep the process alive to verify the client does not block on process exit.
            sleep 10
            break
          fi
        done
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func extractRequestMethods(from logs: String) -> [String] {
        extractRequestObjects(from: logs).compactMap { $0["method"] as? String }
    }

    private func extractRequestObjects(from logs: String) -> [[String: Any]] {
        logs
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> [String: Any]? in
                guard
                    let data = String(line).data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    return nil
                }
                return object
            }
    }

    private func extractModelParam(method: String, from requests: [[String: Any]]) -> String? {
        for request in requests {
            guard request["method"] as? String == method else { continue }
            guard let params = request["params"] as? [String: Any] else { continue }
            if let model = params["model"] as? String {
                return model
            }
        }
        return nil
    }

    private func extractLatencyMs(from line: String?) -> Int? {
        guard let line else { return nil }
        guard let markerRange = line.range(of: "latencyMs=") else { return nil }
        let suffix = line[markerRange.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}

private struct StableMockEngine: TransformEngine {
    func transform(request: TransformRequestPayload) async throws -> String {
        let prefix = request.prompt.prefix(40)
        return "OUT:\(prefix)"
    }
}

private struct DelayedMockEngine: TransformEngine {
    let delayMs: UInt64
    let result: Result<String, Error>

    func transform(request _: TransformRequestPayload) async throws -> String {
        try await Task.sleep(nanoseconds: delayMs * 1_000_000)
        switch result {
        case .success(let output):
            return output
        case .failure(let error):
            throw error
        }
    }
}

private enum DelayedMockEngineError: Error {
    case failed
}
