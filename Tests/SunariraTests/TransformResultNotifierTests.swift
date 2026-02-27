import XCTest
@testable import Sunarira

final class TransformResultNotifierTests: XCTestCase {
    @MainActor
    func testNotifyAlwaysShowsInAppToast() {
        let toastSpy = ToastPresenterSpy()
        let notifier = TransformResultNotifier(
            inAppToastPresenter: toastSpy,
            languageProvider: { .japanese }
        )

        notifier.notify(
            sourceText: String(repeating: "あ", count: 100),
            resultText: String(repeating: "い", count: 80),
            elapsedMilliseconds: 1_240
        )

        XCTAssertEqual(toastSpy.messages, ["100→80文字(80%,1.2秒)"])
    }

    @MainActor
    func testNotifyFormatsEnglishMessage() {
        let toastSpy = ToastPresenterSpy()
        let notifier = TransformResultNotifier(
            inAppToastPresenter: toastSpy,
            languageProvider: { .english }
        )

        notifier.notify(
            sourceText: String(repeating: "a", count: 100),
            resultText: String(repeating: "b", count: 80),
            elapsedMilliseconds: 1_240
        )

        XCTAssertEqual(toastSpy.messages, ["100→80 chars (80%, 1.2s)"])
    }

    @MainActor
    func testNotifyFailureUsesJapaneseMessage() {
        let toastSpy = ToastPresenterSpy()
        let notifier = TransformResultNotifier(
            inAppToastPresenter: toastSpy,
            languageProvider: { .japanese }
        )

        notifier.notifyFailure()

        XCTAssertEqual(toastSpy.messages, ["変換失敗"])
    }

    @MainActor
    func testNotifyFailureUsesAccessibilityMessage() {
        let toastSpy = ToastPresenterSpy()
        let notifier = TransformResultNotifier(
            inAppToastPresenter: toastSpy,
            languageProvider: { .english }
        )

        notifier.notifyFailure(reason: .accessibilityNotGranted)

        XCTAssertEqual(toastSpy.messages, ["Transform failed (Accessibility not granted)"])
    }
}

@MainActor
private final class ToastPresenterSpy: InAppToastPresenting {
    var messages: [String] = []

    func show(message: String) {
        messages.append(message)
    }
}
