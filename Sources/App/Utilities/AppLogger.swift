import CryptoKit
import Foundation
import OSLog

enum AppLogger {
    static let didUpdateNotification = Notification.Name("AppLogger.didUpdate")

    private static let logger = Logger(subsystem: "dev.sunarira.app", category: "app")
    private static let maxEntries = 500
    private static let state = LoggerState()

    static func setIncludeSensitiveText(_ enabled: Bool) {
        state.queue.sync {
            state.includeSensitiveText = enabled
        }
    }

    static func recentEntries(limit: Int = 250) -> [String] {
        state.queue.sync {
            let boundedLimit = max(1, limit)
            return Array(state.entries.suffix(boundedLimit))
        }
    }

    static func clear() {
        state.queue.sync {
            state.entries.removeAll()
        }
        NotificationCenter.default.post(name: didUpdateNotification, object: nil)
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append(level: "INFO", message: message)
    }

    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        append(level: "WARN", message: message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append(level: "ERROR", message: message)
    }

    static func payload(_ label: String, text: String) {
        let hash = sha256Hex(for: text)
        let message: String
        let includeText = state.queue.sync { state.includeSensitiveText }
        if includeText {
            let preview = payloadPreview(text, maxLength: 360)
            message = "\(label): length=\(text.count) sha256=\(hash) text=\"\(preview)\""
        } else {
            message = "\(label): length=\(text.count) sha256=\(hash)"
        }
        info(message)
    }

    private static func append(level: String, message: String) {
        state.queue.sync {
            let timestamp = state.timestampFormatter.string(from: Date())
            let line = "\(timestamp) [\(level)] \(message)"
            state.entries.append(line)
            if state.entries.count > maxEntries {
                state.entries.removeFirst(state.entries.count - maxEntries)
            }
        }
        NotificationCenter.default.post(name: didUpdateNotification, object: nil)
    }

    private static func payloadPreview(_ text: String, maxLength: Int) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\"", with: "\\\"")
        if escaped.count <= maxLength {
            return escaped
        }
        let prefix = escaped.prefix(maxLength)
        return "\(prefix)..."
    }

    private static func sha256Hex(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private final class LoggerState: @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.sunarira.app.logbuffer")
    lazy var timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    var entries: [String] = []
    var includeSensitiveText = false
}
