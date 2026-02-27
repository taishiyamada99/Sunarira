import Foundation

enum StdioJSONRPCClientError: LocalizedError {
    case emptyLaunchCommand
    case launchFailed(String)
    case timeout
    case noResponse(String)
    case invalidResponse
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .emptyLaunchCommand:
            return "Stdio launch command is empty."
        case let .launchFailed(message):
            return "Failed to launch stdio process: \(message)"
        case .timeout:
            return "Timed out waiting for stdio response."
        case let .noResponse(stderr):
            if stderr.isEmpty {
                return "No response from stdio process."
            }
            return "No response from stdio process. stderr: \(stderr)"
        case .invalidResponse:
            return "Invalid stdio JSON-RPC response."
        case let .rpcError(message):
            return message
        }
    }
}

struct EmptyJSONRPCParams: Encodable, Sendable {}

struct StdioJSONRPCClient {
    let launchCommand: String
    var timeout: TimeInterval = 15

    func request(method: String, params: some Encodable & Sendable, initializeFirst: Bool = false) async throws -> Any {
        let command = launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw StdioJSONRPCClientError.emptyLaunchCommand
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let output = try runRequest(
                        command: command,
                        method: method,
                        params: params,
                        initializeFirst: initializeFirst
                    )
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runRequest(
        command: String,
        method: String,
        params: some Encodable & Sendable,
        initializeFirst: Bool
    ) throws -> Any {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw StdioJSONRPCClientError.launchFailed(error.localizedDescription)
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        let requestID = UUID().uuidString
        let initializeID = initializeFirst ? UUID().uuidString : nil
        let state = StdioRequestState(requestID: requestID, initializeID: initializeID)

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            state.appendStdout(data)
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            let stderr = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !stderr.isEmpty else { return }
            state.appendStderr(stderr)
        }

        defer {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            try? stdinPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                Thread.sleep(forTimeInterval: 0.02)
            }
        }

        if initializeFirst {
            let initializePayload = JSONRPCPayload(
                id: initializeID ?? UUID().uuidString,
                method: "initialize",
                params: AnyEncodable(JSONRPCInitializeParams(
                    clientInfo: JSONRPCClientInfo(name: "menu-bar-transformer", version: "0.2.2"),
                    capabilities: JSONRPCCapabilities(experimentalApi: false)
                ))
            )
            let data = try JSONEncoder().encode(initializePayload)
            stdinPipe.fileHandleForWriting.write(data)
            stdinPipe.fileHandleForWriting.write(Data([0x0A]))

            let initializedPayload = JSONRPCNotificationPayload(
                method: "initialized",
                params: AnyEncodable(EmptyJSONRPCParams())
            )
            let initializedData = try JSONEncoder().encode(initializedPayload)
            stdinPipe.fileHandleForWriting.write(initializedData)
            stdinPipe.fileHandleForWriting.write(Data([0x0A]))
        }

        let requestPayload = JSONRPCPayload(
            id: requestID,
            method: method,
            params: AnyEncodable(params)
        )
        let requestData = try JSONEncoder().encode(requestPayload)
        stdinPipe.fileHandleForWriting.write(requestData)
        stdinPipe.fileHandleForWriting.write(Data([0x0A]))

        let responseState = state.waitForResponse(timeout: timeout)
        if responseState.timedOut {
            if responseState.matched == nil, responseState.fallback == nil {
                if responseState.stderr.isEmpty {
                    throw StdioJSONRPCClientError.timeout
                }
                throw StdioJSONRPCClientError.noResponse(responseState.stderr)
            }
        }

        guard let response = responseState.matched ?? responseState.fallback else {
            throw StdioJSONRPCClientError.noResponse(responseState.stderr)
        }

        if
            let errorObject = response["error"] as? [String: Any],
            let message = errorObject["message"] as? String
        {
            throw StdioJSONRPCClientError.rpcError(message)
        }

        guard let result = response["result"] else {
            throw StdioJSONRPCClientError.invalidResponse
        }

        return result
    }

}

private struct JSONRPCPayload: Encodable {
    let jsonrpc = "2.0"
    let id: String
    let method: String
    let params: AnyEncodable
}

private struct JSONRPCNotificationPayload: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: AnyEncodable
}

private struct JSONRPCInitializeParams: Encodable {
    let clientInfo: JSONRPCClientInfo
    let capabilities: JSONRPCCapabilities
}

private struct JSONRPCClientInfo: Encodable {
    let name: String
    let version: String
}

private struct JSONRPCCapabilities: Encodable {
    let experimentalApi: Bool
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ wrapped: T) {
        encodeClosure = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

private struct StdioRequestOutcome {
    let matched: [String: Any]?
    let fallback: [String: Any]?
    let stderr: String
    let timedOut: Bool
}

private final class StdioRequestState: @unchecked Sendable {
    private let requestID: String
    private let initializeID: String?
    private let semaphore = DispatchSemaphore(value: 0)
    private let queue = DispatchQueue(label: "StdioJSONRPCClient.requestState", qos: .userInitiated)

    private var stdoutBuffer = Data()
    private var matchedResponse: [String: Any]?
    private var fallbackResponse: [String: Any]?
    private var stderrMessages: [String] = []
    private var didSignal = false

    init(requestID: String, initializeID: String?) {
        self.requestID = requestID
        self.initializeID = initializeID
    }

    func appendStdout(_ data: Data) {
        queue.sync {
            stdoutBuffer.append(data)

            while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
                let lineData = Data(stdoutBuffer.prefix(upTo: newlineIndex))
                stdoutBuffer.removeSubrange(...newlineIndex)

                guard
                    !lineData.isEmpty,
                    let object = try? JSONSerialization.jsonObject(with: lineData),
                    let dictionary = object as? [String: Any]
                else {
                    continue
                }

                if responseIDMatches(dictionary["id"], requestID: requestID) {
                    matchedResponse = dictionary
                    signalIfNeeded()
                    continue
                }

                if
                    let initializeID,
                    responseIDMatches(dictionary["id"], requestID: initializeID)
                {
                    continue
                }

                if dictionary["result"] != nil || dictionary["error"] != nil {
                    fallbackResponse = dictionary
                    signalIfNeeded()
                }
            }
        }
    }

    func appendStderr(_ message: String) {
        queue.sync {
            stderrMessages.append(message)
            if stderrMessages.count > 20 {
                stderrMessages.removeFirst(stderrMessages.count - 20)
            }
        }
    }

    func waitForResponse(timeout: TimeInterval) -> StdioRequestOutcome {
        let timedOut = semaphore.wait(timeout: .now() + timeout) == .timedOut
        return queue.sync {
            StdioRequestOutcome(
                matched: matchedResponse,
                fallback: fallbackResponse,
                stderr: stderrMessages.joined(separator: " | "),
                timedOut: timedOut
            )
        }
    }

    private func signalIfNeeded() {
        guard !didSignal else { return }
        didSignal = true
        semaphore.signal()
    }
}

private func responseIDMatches(_ rawID: Any?, requestID: String) -> Bool {
    if let value = rawID as? String {
        return value == requestID
    }
    if let value = rawID as? NSNumber {
        return value.stringValue == requestID
    }
    return false
}
