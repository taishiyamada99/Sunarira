import Foundation

struct TransformResultMessageFormatter {
    func message(for metrics: TransformMetrics, language: InterfaceLanguage) -> String {
        switch language {
        case .japanese:
            return "\(metrics.sourceCount)→\(metrics.resultCount)文字(\(metrics.compressionPercent)%,\(metrics.elapsedSecondsOneDecimal)秒)"
        case .english:
            return "\(metrics.sourceCount)→\(metrics.resultCount) chars (\(metrics.compressionPercent)%, \(metrics.elapsedSecondsOneDecimal)s)"
        case .german:
            return "\(metrics.sourceCount)→\(metrics.resultCount) Zeichen (\(metrics.compressionPercent)%, \(metrics.elapsedSecondsOneDecimal)s)"
        case .spanish:
            return "\(metrics.sourceCount)→\(metrics.resultCount) caracteres (\(metrics.compressionPercent)%, \(metrics.elapsedSecondsOneDecimal)s)"
        case .french:
            return "\(metrics.sourceCount)→\(metrics.resultCount) caractères (\(metrics.compressionPercent)%, \(metrics.elapsedSecondsOneDecimal)s)"
        }
    }
}
