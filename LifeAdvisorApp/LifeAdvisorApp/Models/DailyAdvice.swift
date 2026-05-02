import Foundation
import SwiftData

@Model
final class DailyAdvice {
    @Attribute(.unique) var date: String
    var adviceText: String
    var createdAt: Date

    init(date: String, adviceText: String, createdAt: Date = Date()) {
        self.date = date
        self.adviceText = adviceText
        self.createdAt = createdAt
    }

    static func dateKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
