import ApplicationServices
import AppKit
import Foundation

struct AccessibilityService {
    func isTrusted(promptIfNeeded: Bool) -> Bool {
        let trusted = AXIsProcessTrusted()
        guard promptIfNeeded, !trusted else {
            return trusted
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
