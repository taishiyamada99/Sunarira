import Foundation

struct TransformContext: Codable, Equatable {
    var modeID: UUID
    var modeDisplayName: String
    var promptTemplate: String
    var model: String
    var inputText: String
}
