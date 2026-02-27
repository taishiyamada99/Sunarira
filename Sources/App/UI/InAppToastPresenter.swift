import AppKit
import Foundation

@MainActor
protocol InAppToastPresenting: AnyObject {
    func show(message: String)
}

@MainActor
final class InAppToastPresenter: InAppToastPresenting {
    private let displayDuration: TimeInterval
    private let fadeDuration: TimeInterval
    private let edgePadding: CGFloat
    private let horizontalPadding: CGFloat = 14
    private let verticalPadding: CGFloat = 9
    private let minimumWidth: CGFloat = 180
    private let maximumWidthCap: CGFloat = 820
    private let minimumHeight: CGFloat = 36
    private let widthSafetyBuffer: CGFloat = 24

    private var panel: NSPanel?
    private var messageLabel: NSTextField?
    private var hideTask: Task<Void, Never>?
    private var presentationID = 0

    init(
        displayDuration: TimeInterval = 2.5,
        fadeDuration: TimeInterval = 0.15,
        edgePadding: CGFloat = 16
    ) {
        self.displayDuration = displayDuration
        self.fadeDuration = fadeDuration
        self.edgePadding = edgePadding
    }

    deinit {
        hideTask?.cancel()
    }

    func show(message: String) {
        presentationID += 1
        let currentPresentationID = presentationID
        hideTask?.cancel()

        let panel = ensurePanel()
        let label = ensureMessageLabel(in: panel)
        label.stringValue = message
        let screen = preferredScreen()

        let contentSize = measuredContentSize(
            for: message,
            font: label.font ?? .systemFont(ofSize: 13),
            screen: screen
        )
        panel.setContentSize(contentSize)
        layoutMessageLabel()
        position(panel, on: screen)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            animateAlpha(panel, to: 1.0, duration: fadeDuration)
        } else {
            panel.orderFrontRegardless()
            panel.alphaValue = 1.0
        }

        hideTask = Task { [weak self] in
            guard let self else { return }
            let nanos = UInt64(self.displayDuration * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self.hideIfCurrent(presentationID: currentPresentationID)
        }
    }

    private func hideIfCurrent(presentationID: Int) {
        guard presentationID == self.presentationID, let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeDuration
            panel.animator().alphaValue = 0.0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard let self, presentationID == self.presentationID else { return }
                panel?.orderOut(nil)
            }
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let initialFrame = NSRect(x: 0, y: 0, width: minimumWidth, height: minimumHeight)
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: initialFrame.size))
        container.autoresizingMask = [.width, .height]
        container.material = .hudWindow
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true

        panel.contentView = container
        self.panel = panel
        return panel
    }

    private func ensureMessageLabel(in panel: NSPanel) -> NSTextField {
        if let messageLabel {
            return messageLabel
        }

        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byCharWrapping
        label.maximumNumberOfLines = 0
        label.autoresizingMask = [.width, .height]

        panel.contentView?.addSubview(label)
        messageLabel = label
        return label
    }

    private func layoutMessageLabel() {
        guard let panel, let messageLabel else { return }
        let insetBounds = panel.contentView?.bounds.insetBy(dx: horizontalPadding, dy: verticalPadding) ?? .zero
        messageLabel.frame = insetBounds
    }

    private func measuredContentSize(for message: String, font: NSFont, screen: NSScreen?) -> NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let screenBoundWidth = max(minimumWidth, (screen?.visibleFrame.width ?? maximumWidthCap) - edgePadding * 2)
        let maximumWidth = min(maximumWidthCap, screenBoundWidth)
        let unconstrainedTextSize = (message as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).size
        let preferredWidth = ceil(unconstrainedTextSize.width) + horizontalPadding * 2 + widthSafetyBuffer
        let width = min(max(preferredWidth, minimumWidth), maximumWidth)

        let textConstraintWidth = max(1, width - horizontalPadding * 2)
        let constrainedTextSize = (message as NSString).boundingRect(
            with: NSSize(width: textConstraintWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).size
        let maximumPanelHeight = max(
            minimumHeight,
            (screen?.visibleFrame.height ?? 720) - edgePadding * 2
        )
        let maximumTextHeight = max(1, maximumPanelHeight - verticalPadding * 2)
        let textHeight = min(ceil(constrainedTextSize.height), maximumTextHeight)

        let height = max(textHeight + verticalPadding * 2, minimumHeight)
        return NSSize(width: width, height: height)
    }

    private func position(_ panel: NSPanel, on screen: NSScreen?) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - edgePadding,
            y: visible.maxY - size.height - edgePadding
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }

        if let keyWindowScreen = NSApp.keyWindow?.screen {
            return keyWindowScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func animateAlpha(
        _ panel: NSPanel,
        to alphaValue: CGFloat,
        duration: TimeInterval
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = alphaValue
        }
    }
}
