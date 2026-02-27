import Foundation

@MainActor
final class TransformResultNotifier {
    enum FailureReason {
        case generic
        case accessibilityNotGranted
    }

    private let inAppToastPresenter: InAppToastPresenting
    private let messageFormatter: TransformResultMessageFormatter
    private let languageProvider: () -> InterfaceLanguage

    init(
        inAppToastPresenter: InAppToastPresenting,
        messageFormatter: TransformResultMessageFormatter = TransformResultMessageFormatter(),
        languageProvider: @escaping () -> InterfaceLanguage
    ) {
        self.inAppToastPresenter = inAppToastPresenter
        self.messageFormatter = messageFormatter
        self.languageProvider = languageProvider
    }

    func notify(sourceText: String, resultText: String, elapsedMilliseconds: Int) {
        let metrics = TransformMetrics(
            sourceText: sourceText,
            resultText: resultText,
            elapsedMilliseconds: elapsedMilliseconds
        )
        let language = languageProvider()
        let message = messageFormatter.message(for: metrics, language: language)

        inAppToastPresenter.show(message: message)
    }

    func notifyFailure(reason: FailureReason = .generic) {
        let language = languageProvider()
        let message: String

        switch reason {
        case .generic:
            message = language.localized(
                english: "Transform failed",
                japanese: "変換失敗",
                german: "Umformung fehlgeschlagen",
                spanish: "Transformación fallida",
                french: "Échec de la transformation"
            )
        case .accessibilityNotGranted:
            message = language.localized(
                english: "Transform failed (Accessibility not granted)",
                japanese: "変換失敗(アクセシビリティ未許可)",
                german: "Umformung fehlgeschlagen (Bedienungshilfen nicht gewährt)",
                spanish: "Transformación fallida (Accesibilidad no concedida)",
                french: "Échec de la transformation (Accessibilité non accordée)"
            )
        }

        inAppToastPresenter.show(message: message)
    }
}
