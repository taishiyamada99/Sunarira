import ApplicationServices
import Foundation

enum CaptureScope {
    case selection
    case fullText
}

struct CapturedText {
    let text: String
    let scope: CaptureScope
    let element: AXUIElement
}

enum ReplaceMethod {
    case keystrokeInjection
    case axAttributeSet
}

enum AXTextServiceError: LocalizedError {
    case accessibilityNotGranted
    case focusedElementUnavailable
    case focusedElementNotEditable
    case textUnavailable
    case replacementFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Accessibility permission is not granted."
        case .focusedElementUnavailable:
            return "Focused element is not available."
        case .focusedElementNotEditable:
            return "Focused element is not an editable text input."
        case .textUnavailable:
            return "Text content is not available on the focused element."
        case .replacementFailed:
            return "Failed to replace text in the focused element."
        }
    }
}

final class AXTextService {
    private static let clipboardRestoreDelayMicros: useconds_t = 600_000
    private let clipboardService: ClipboardService

    init(accessibilityService _: AccessibilityService, clipboardService: ClipboardService) {
        self.clipboardService = clipboardService
    }

    func captureFocusedText() throws -> CapturedText {
        let focusedElement = try focusedUIElement()
        guard isEditableTextElement(focusedElement) else {
            throw AXTextServiceError.focusedElementNotEditable
        }

        if let selectedText = copyStringAttribute(kAXSelectedTextAttribute, from: focusedElement), !selectedText.isEmpty {
            return CapturedText(text: selectedText, scope: .selection, element: focusedElement)
        }

        if let valueText = copyStringAttribute(kAXValueAttribute, from: focusedElement), !valueText.isEmpty {
            return CapturedText(text: valueText, scope: .fullText, element: focusedElement)
        }

        throw AXTextServiceError.textUnavailable
    }

    func replaceText(_ text: String, using capture: CapturedText) throws -> ReplaceMethod {
        if replaceByKeystrokeInjection(text, scope: capture.scope) {
            return .keystrokeInjection
        }

        if replaceByAXSetValue(text, using: capture) {
            return .axAttributeSet
        }

        throw AXTextServiceError.replacementFailed
    }

    func copyToClipboard(_ text: String) {
        clipboardService.writeString(text)
    }

    private func focusedUIElement() throws -> AXUIElement {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: AnyObject?
        let status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObject)

        if status == .apiDisabled {
            throw AXTextServiceError.accessibilityNotGranted
        }

        guard status == .success, let focusedObject else {
            throw AXTextServiceError.focusedElementUnavailable
        }

        return focusedObject as! AXUIElement
    }

    private func copyStringAttribute(_ key: String, from element: AXUIElement) -> String? {
        var value: AnyObject?
        let status = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard status == .success else {
            return nil
        }

        return value as? String
    }

    private func copyBoolAttribute(_ key: String, from element: AXUIElement) -> Bool? {
        var value: AnyObject?
        let status = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        guard status == .success else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private func isAttributeSettable(_ key: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        let status = AXUIElementIsAttributeSettable(element, key as CFString, &settable)
        return status == .success && settable.boolValue
    }

    private func isEditableTextElement(_ element: AXUIElement) -> Bool {
        if copyBoolAttribute("AXEditable", from: element) == true {
            return true
        }

        if isAttributeSettable(kAXValueAttribute, on: element) {
            return true
        }

        guard let role = copyStringAttribute(kAXRoleAttribute, from: element) else {
            return false
        }

        let editableRoles = Set([
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            "AXSearchField",
            kAXComboBoxRole as String
        ])
        return editableRoles.contains(role)
    }

    private func replaceByKeystrokeInjection(_ text: String, scope: CaptureScope) -> Bool {
        let snapshot = clipboardService.snapshot()
        clipboardService.writeString(text)

        let success: Bool
        switch scope {
        case .selection:
            success = KeySender.paste()
        case .fullText:
            success = KeySender.selectAll() && KeySender.paste()
        }

        // Keep transformed text in the clipboard long enough for slower apps to finish reading paste data.
        usleep(Self.clipboardRestoreDelayMicros)
        clipboardService.restore(snapshot)
        return success
    }

    private func replaceByAXSetValue(_ text: String, using capture: CapturedText) -> Bool {
        let attribute: String
        switch capture.scope {
        case .selection:
            attribute = kAXSelectedTextAttribute
        case .fullText:
            attribute = kAXValueAttribute
        }

        let status = AXUIElementSetAttributeValue(capture.element, attribute as CFString, text as CFTypeRef)
        return status == .success
    }
}
