import Foundation
import SwiftData

@Model
final class Recommendation {
    @Attribute(.unique) var date: String
    var recommendationText: String
    var createdAt: Date

    init(date: String, recommendationText: String, createdAt: Date = Date()) {
        self.date = date
        self.recommendationText = recommendationText
        self.createdAt = createdAt
    }
}
