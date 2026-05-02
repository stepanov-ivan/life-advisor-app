import Foundation
import SwiftData

enum MealEventStatus: String, Codable {
    case empty
    case raw
    case structured
    case skipped
}

@Model
final class MealEvent {
    @Attribute(.unique) var id: UUID
    var windowLabel: String
    var timestamp: Date
    var statusRaw: String
    var rawText: String?
    var calories: Double
    var proteins: Double
    var fats: Double
    var carbs: Double

    @Relationship(deleteRule: .cascade, inverse: \Ingredient.mealEvent)
    var ingredients: [Ingredient] = []

    var status: MealEventStatus {
        get { MealEventStatus(rawValue: statusRaw) ?? .empty }
        set { statusRaw = newValue.rawValue }
    }

    init(
        windowLabel: String,
        timestamp: Date = Date(),
        status: MealEventStatus = .raw,
        rawText: String? = nil
    ) {
        self.id = UUID()
        self.windowLabel = windowLabel
        self.timestamp = timestamp
        self.statusRaw = status.rawValue
        self.rawText = rawText
        self.calories = 0
        self.proteins = 0
        self.fats = 0
        self.carbs = 0
    }

    func recalculateAggregates() {
        calories = ingredients.reduce(0) { $0 + $1.calories }
        proteins = ingredients.reduce(0) { $0 + $1.proteins }
        fats = ingredients.reduce(0) { $0 + $1.fats }
        carbs = ingredients.reduce(0) { $0 + $1.carbs }
    }
}
