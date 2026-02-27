import CoreGraphics
import Foundation

enum KeySender {
    @discardableResult
    static func copy() -> Bool {
        sendCombo(keyCode: 8, modifiers: .maskCommand)
    }

    @discardableResult
    static func paste() -> Bool {
        sendCombo(keyCode: 9, modifiers: .maskCommand)
    }

    @discardableResult
    static func selectAll() -> Bool {
        sendCombo(keyCode: 0, modifiers: .maskCommand)
    }

    @discardableResult
    private static func sendCombo(keyCode: CGKeyCode, modifiers: CGEventFlags) -> Bool {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        usleep(40_000)
        return true
    }
}
