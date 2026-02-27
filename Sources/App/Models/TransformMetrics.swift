import Foundation

struct TransformMetrics: Equatable {
    let sourceCount: Int
    let resultCount: Int
    let compressionPercent: Int
    let elapsedMilliseconds: Int

    var elapsedSecondsOneDecimal: String {
        let tenths = (elapsedMilliseconds + 50) / 100
        return "\(tenths / 10).\(tenths % 10)"
    }

    init(sourceText: String, resultText: String, elapsedMilliseconds: Int) {
        sourceCount = sourceText.count
        resultCount = resultText.count
        self.elapsedMilliseconds = max(0, elapsedMilliseconds)

        if sourceCount > 0 {
            compressionPercent = Int((Double(resultCount) / Double(sourceCount)) * 100.0)
        } else {
            compressionPercent = 0
        }
    }
}
