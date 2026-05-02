import Foundation
import SwiftData

@Model
final class FoodItem {
    @Attribute(.unique) var name: String
    var category: String
    var calories: Double
    var proteins: Double
    var fats: Double
    var carbs: Double
    var fiber: Double

    init(
        name: String,
        category: String,
        calories: Double,
        proteins: Double,
        fats: Double,
        carbs: Double,
        fiber: Double = 0
    ) {
        self.name = name
        self.category = category
        self.calories = calories
        self.proteins = proteins
        self.fats = fats
        self.carbs = carbs
        self.fiber = fiber
    }
}
