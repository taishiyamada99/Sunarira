import Foundation

enum CodexAppServerStdioEngineError: LocalizedError {
    case requestFailed(String)
    case timeout
    case noOutput

    var errorDescription: String? {
        switch self {
        case let .requestFailed(message):
            return message
        case .timeout:
            return "Timed out waiting for App Server response."
        case .noOutput:
            return "App Server returned no transformed output."
        }
    }
}

struct CodexAppServerStdioEngine: TransformEngine {
    let launchCommand: String
    var timeout: TimeInterval = 90

    func transform(request: TransformRequestPayload) async throws -> String {
        let command = launchCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else {
            throw CodexAppServerStdioEngineError.requestFailed("Stdio launch command is empty.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let session = CodexAppServerStdioSession(launchCommand: command, timeout: timeout)
                do {
                    let output = try session.transform(request: request)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private final class CodexAppServerStdioSession: @unchecked Sendable {
    private let launchCommand: String
    private let timeout: TimeInterval

    private let queue = DispatchQueue(label: "CodexAppServerStdioSession", qos: .userInitiated)
    private let completionSemaphore = DispatchSemaphore(value: 0)
    private var completionSignaled = false

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    private var stdoutBuffer = Data()
    private var pendingResponses: [String: PendingResponse] = [:]

    private var activeThreadID: String?
    private var activeTurnID: String?
    private var turnFinished = false
    private var terminalErrorMessage: String?
    private var stderrMessages: [String] = []
    private var assistantTextSegments: [String] = []

    init(launchCommand: String, timeout: TimeInterval) {
        self.launchCommand = launchCommand
        self.timeout = timeout
    }

    func transform(request: TransformRequestPayload) throws -> String {
        try startProcess()
        defer { stopProcess() }

        _ = try sendRequest(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "menu-bar-transformer",
                    "version": "0.2.2"
                ],
                "capabilities": [
                    "experimentalApi": false
                ]
            ]
        )

        let threadResult = try sendRequest(
            method: "thread/start",
            params: [
                "model": request.model,
                "cwd": FileManager.default.currentDirectoryPath,
                "approvalPolicy": "never",
                "sandbox": "workspace-write",
                "baseInstructions": "You are a deterministic text transformer. Never use tools. Return transformed text only."
            ]
        )

        let threadID = try extractThreadID(from: threadResult)
        activeThreadID = threadID

        let turnResult = try sendRequest(
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [
                    [
                        "type": "text",
                        "text": request.prompt
                    ]
                ],
                "model": request.model,
                "summary": "none",
                "effort": "low",
                "approvalPolicy": "never"
            ]
        )

        activeTurnID = extractTurnID(from: turnResult)

        let completed = completionSemaphore.wait(timeout: .now() + timeout)
        if completed == .timedOut {
            // Final read fallback before treating as timeout.
            if let fallback = try? fetchFinalOutputFromThreadRead(), !fallback.isEmpty {
                return fallback
            }
            let stderrSummary = queue.sync { latestStderrSummary() }
            if !stderrSummary.isEmpty {
                throw CodexAppServerStdioEngineError.requestFailed("Timed out waiting for App Server response. stderr: \(stderrSummary)")
            }
            throw CodexAppServerStdioEngineError.timeout
        }

        if let errorMessage = queue.sync(execute: { terminalErrorMessage }), !errorMessage.isEmpty {
            throw CodexAppServerStdioEngineError.requestFailed(errorMessage)
        }

        if let fromRead = try? fetchFinalOutputFromThreadRead(), !fromRead.isEmpty {
            return fromRead
        }

        let merged = queue.sync {
            assistantTextSegments
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !merged.isEmpty {
            return merged
        }

        let stderrSummary = queue.sync { latestStderrSummary() }
        if !stderrSummary.isEmpty {
            throw CodexAppServerStdioEngineError.requestFailed("App Server returned no transformed output. stderr: \(stderrSummary)")
        }

        throw CodexAppServerStdioEngineError.noOutput
    }

    private func fetchFinalOutputFromThreadRead() throws -> String {
        guard let threadID = queue.sync(execute: { activeThreadID }) else {
            return ""
        }

        let result = try sendRequest(
            method: "thread/read",
            params: [
                "threadId": threadID,
                "includeTurns": true
            ]
        )

        let output = extractAssistantTextFromThreadRead(result)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !output.isEmpty {
            queue.sync {
                if assistantTextSegments.isEmpty {
                    assistantTextSegments.append(output)
                }
            }
        }

        return output
    }

    private func startProcess() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", launchCommand]

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
            throw CodexAppServerStdioEngineError.requestFailed("Failed to launch stdio process: \(error.localizedDescription)")
        }

        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading

        stdoutHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.queue.async {
                self.appendStdoutData(data)
            }
        }

        stderrHandle?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }

            let stderr = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stderr.isEmpty {
                self.queue.async {
                    self.appendStderrMessage(stderr)
                }
            }
        }
    }

    private func stopProcess() {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        try? stdinHandle?.close()

        if let process, process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.05)
        }

        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
    }

    private func sendRequest(method: String, params: Any) throws -> Any {
        let requestID = UUID().uuidString
        let requestObject: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params
        ]

        let requestData = try JSONSerialization.data(withJSONObject: requestObject, options: [])
        let payload = requestData + Data([0x0A])

        let pending = PendingResponse()
        queue.sync {
            pendingResponses[requestID] = pending
        }

        stdinHandle?.write(payload)

        let waitResult = pending.semaphore.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            _ = queue.sync {
                pendingResponses.removeValue(forKey: requestID)
            }
            throw CodexAppServerStdioEngineError.timeout
        }

        let response = queue.sync { () -> [String: Any]? in
            defer { pendingResponses.removeValue(forKey: requestID) }
            return pending.response
        }

        guard let response else {
            throw CodexAppServerStdioEngineError.requestFailed("No response from App Server.")
        }

        if
            let error = response["error"] as? [String: Any],
            let message = error["message"] as? String
        {
            throw CodexAppServerStdioEngineError.requestFailed(message)
        }

        guard let result = response["result"] else {
            throw CodexAppServerStdioEngineError.requestFailed("Invalid App Server response.")
        }

        return result
    }

    private func appendStdoutData(_ data: Data) {
        stdoutBuffer.append(data)

        while true {
            guard let newline = stdoutBuffer.firstIndex(of: 0x0A) else { break }
            let lineData = stdoutBuffer.prefix(upTo: newline)
            stdoutBuffer.removeSubrange(...newline)
            guard !lineData.isEmpty else { continue }
            handleLineData(Data(lineData))
        }
    }

    private func handleLineData(_ data: Data) {
        guard
            let line = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !line.isEmpty
        else {
            return
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: []),
            let json = object as? [String: Any]
        else {
            return
        }

        if let id = requestIDString(json["id"]), let pending = pendingResponses[id] {
            pending.response = json
            pending.semaphore.signal()
            return
        }

        // Some wrappers may fail to echo the request id correctly.
        // We issue one in-flight request at a time, so a single pending response can be safely matched.
        if json["result"] != nil || json["error"] != nil {
            if pendingResponses.count == 1, let pending = pendingResponses.values.first {
                pending.response = json
                pending.semaphore.signal()
                return
            }
        }

        if
            let method = json["method"] as? String,
            let id = json["id"]
        {
            handleServerRequest(method: method, id: id, params: json["params"] as? [String: Any] ?? [:])
            return
        }

        guard
            let method = json["method"] as? String,
            let params = json["params"] as? [String: Any]
        else {
            return
        }

        handleNotification(method: method, params: params)
    }

    private func handleServerRequest(method: String, id: Any, params _: [String: Any]) {
        let result: [String: Any]

        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            result = ["decision": "decline"]
        case "item/tool/requestUserInput":
            result = ["answers": [String: Any]()]
        case "item/tool/call":
            result = [
                "success": false,
                "contentItems": [
                    [
                        "type": "inputText",
                        "text": "Tool use is disabled for this deterministic transformer."
                    ]
                ]
            ]
        default:
            result = [:]
        }

        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]

        if !JSONSerialization.isValidJSONObject(response) {
            response = [
                "jsonrpc": "2.0",
                "id": id,
                "result": [String: Any]()
            ]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: response, options: []) else {
            return
        }
        stdinHandle?.write(data + Data([0x0A]))
    }

    private func handleNotification(method: String, params: [String: Any]) {
        switch method {
        case "thread/started":
            if let threadID = notificationThreadID(params) {
                activeThreadID = threadID
            }
        case "turn/started":
            if let turnID = notificationTurnID(params) {
                activeTurnID = turnID
            }
        case "item/agentMessage/delta":
            guard notificationMatchesActiveRun(params) else { return }
            if let delta = params["delta"] as? String {
                appendAssistantSegment(delta)
            }
        case "item/completed":
            guard notificationMatchesActiveRun(params) else { return }
            if let item = params["item"] as? [String: Any] {
                extractAssistantText(from: item).forEach(appendAssistantSegment(_:))
            }
        case "turn/completed":
            guard notificationMatchesActiveRun(params) else { return }
            if
                let turn = params["turn"] as? [String: Any],
                let status = turn["status"] as? String,
                status == "failed"
            {
                terminalErrorMessage = messageFromError(turn["error"]) ?? "Transform failed."
            }
            markTurnFinishedIfNeeded()
        case "error":
            let willRetry = (params["willRetry"] as? Bool) ?? false
            if !willRetry, let error = params["error"] as? [String: Any], let message = error["message"] as? String {
                terminalErrorMessage = message
                markTurnFinishedIfNeeded()
            }
        default:
            break
        }
    }

    private func notificationMatchesActiveRun(_ params: [String: Any]) -> Bool {
        if let threadID = notificationThreadID(params), let activeThreadID, threadID != activeThreadID {
            return false
        }

        if let turnID = notificationTurnID(params), let activeTurnID, turnID != activeTurnID {
            return false
        }

        return true
    }

    private func notificationThreadID(_ params: [String: Any]) -> String? {
        if let threadID = params["threadId"] as? String {
            return threadID
        }

        if
            let thread = params["thread"] as? [String: Any],
            let threadID = thread["id"] as? String
        {
            return threadID
        }

        if
            let turn = params["turn"] as? [String: Any],
            let threadID = turn["threadId"] as? String
        {
            return threadID
        }

        return nil
    }

    private func notificationTurnID(_ params: [String: Any]) -> String? {
        if let turnID = params["turnId"] as? String {
            return turnID
        }

        if
            let turn = params["turn"] as? [String: Any],
            let turnID = turn["id"] as? String
        {
            return turnID
        }

        if
            let item = params["item"] as? [String: Any],
            let turnID = item["turnId"] as? String
        {
            return turnID
        }

        return nil
    }

    private func appendAssistantSegment(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        assistantTextSegments.append(trimmed)
    }

    private func appendStderrMessage(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stderrMessages.append(trimmed)
        if stderrMessages.count > 10 {
            stderrMessages.removeFirst(stderrMessages.count - 10)
        }
    }

    private func latestStderrSummary() -> String {
        stderrMessages.joined(separator: " | ")
    }

    private func extractAssistantTextFromThreadRead(_ result: Any) -> [String] {
        guard
            let object = result as? [String: Any],
            let thread = object["thread"] as? [String: Any],
            let turns = thread["turns"] as? [Any]
        else {
            return []
        }

        var collected: [String] = []
        for turnValue in turns {
            guard let turn = turnValue as? [String: Any] else { continue }
            guard let items = turn["items"] as? [Any] else { continue }
            for itemValue in items {
                guard let item = itemValue as? [String: Any] else { continue }
                collected.append(contentsOf: extractAssistantText(from: item))
            }
        }
        return collected
    }

    private func extractAssistantText(from item: [String: Any]) -> [String] {
        let type = (item["type"] as? String)?.lowercased() ?? ""
        let role = (item["role"] as? String)?.lowercased() ?? ""
        let author = (item["author"] as? String)?.lowercased() ?? ""
        let isAssistant = type.contains("assistant") || type.contains("agentmessage") || role == "assistant" || author == "assistant"
        guard isAssistant else { return [] }

        var parts: [String] = []
        parts.append(contentsOf: extractTextFragments(from: item))
        return parts
    }

    private func extractTextFragments(from value: Any) -> [String] {
        if let text = value as? String {
            return [text]
        }

        if let list = value as? [Any] {
            return list.flatMap(extractTextFragments(from:))
        }

        guard let object = value as? [String: Any] else {
            return []
        }

        var fragments: [String] = []

        for key in ["text", "message", "output_text", "delta", "value"] {
            if let text = object[key] as? String {
                fragments.append(text)
            }
        }

        for key in ["content", "output", "items", "data"] {
            if let nested = object[key] {
                fragments.append(contentsOf: extractTextFragments(from: nested))
            }
        }

        return fragments
    }

    private func markTurnFinishedIfNeeded() {
        guard !turnFinished else { return }
        turnFinished = true
        guard !completionSignaled else { return }
        completionSignaled = true
        completionSemaphore.signal()
    }

    private func extractThreadID(from result: Any) throws -> String {
        guard let object = result as? [String: Any] else {
            throw CodexAppServerStdioEngineError.requestFailed("thread/start returned an invalid payload.")
        }

        if
            let thread = object["thread"] as? [String: Any],
            let id = thread["id"] as? String,
            !id.isEmpty
        {
            return id
        }

        if let id = object["threadId"] as? String, !id.isEmpty {
            return id
        }

        throw CodexAppServerStdioEngineError.requestFailed("thread/start did not return thread.id.")
    }

    private func extractTurnID(from result: Any) -> String? {
        guard let object = result as? [String: Any] else {
            return nil
        }

        if
            let turn = object["turn"] as? [String: Any],
            let id = turn["id"] as? String,
            !id.isEmpty
        {
            return id
        }

        if let id = object["turnId"] as? String, !id.isEmpty {
            return id
        }

        return nil
    }

    private func messageFromError(_ raw: Any?) -> String? {
        guard let object = raw as? [String: Any] else { return nil }
        return object["message"] as? String
    }

    private func requestIDString(_ raw: Any?) -> String? {
        if let string = raw as? String {
            return string
        }
        if let number = raw as? NSNumber {
            return number.stringValue
        }
        return nil
    }
}

private final class PendingResponse {
    let semaphore = DispatchSemaphore(value: 0)
    var response: [String: Any]?
}
