import Foundation

enum ClipboardFallbackError: LocalizedError {
    case noClipboardText
    case noCapturedText
    case replaceFailed

    var errorDescription: String? {
        switch self {
        case .noClipboardText:
            return "Clipboard does not contain text."
        case .noCapturedText:
            return "Could not copy selected or full text from focused app."
        case .replaceFailed:
            return "Could not paste transformed text back into focused app."
        }
    }
}

@MainActor
final class ClipboardFallbackService {
    private static let clipboardRestoreDelayMicros: useconds_t = 600_000
    private let clipboardService: ClipboardService

    init(clipboardService: ClipboardService) {
        self.clipboardService = clipboardService
    }

    func transformUsingFocusedAppClipboard(
        transform: @MainActor @escaping (String) async throws -> String
    ) async throws {
        let snapshot = clipboardService.snapshot()
        defer {
            // Keep transformed clipboard content available long enough for the target app paste pipeline.
            usleep(Self.clipboardRestoreDelayMicros)
            clipboardService.restore(snapshot)
        }

        var capturedText: String?
        var baselineChangeCount = snapshot.changeCount

        if KeySender.copy() {
            usleep(80_000)
            let copiedChangeCount = clipboardService.currentChangeCount()
            if copiedChangeCount != baselineChangeCount {
                capturedText = clipboardService.readString()
                baselineChangeCount = copiedChangeCount
            }
        }

        if capturedText?.isEmpty != false {
            if KeySender.selectAll(), KeySender.copy() {
                usleep(80_000)
                let copiedChangeCount = clipboardService.currentChangeCount()
                if copiedChangeCount != baselineChangeCount {
                    capturedText = clipboardService.readString()
                }
            }
        }

        guard let source = capturedText, !source.isEmpty else {
            throw ClipboardFallbackError.noCapturedText
        }

        let transformed = try await transform(source)
        clipboardService.writeString(transformed)
        guard KeySender.paste() else {
            throw ClipboardFallbackError.replaceFailed
        }
    }

    func transformClipboardOnly(
        transform: @MainActor @escaping (String) async throws -> String
    ) async throws {
        guard let source = clipboardService.readString(), !source.isEmpty else {
            throw ClipboardFallbackError.noClipboardText
        }

        let transformed = try await transform(source)
        clipboardService.writeString(transformed)
    }
}
