import AppKit
import Foundation

struct ClipboardSnapshot {
    let stringValue: String?
    let changeCount: Int
}

final class ClipboardService {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func snapshot() -> ClipboardSnapshot {
        ClipboardSnapshot(
            stringValue: pasteboard.string(forType: .string),
            changeCount: pasteboard.changeCount
        )
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        pasteboard.clearContents()
        if let value = snapshot.stringValue {
            pasteboard.setString(value, forType: .string)
        }
    }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    func writeString(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func currentChangeCount() -> Int {
        pasteboard.changeCount
    }
}
