import Foundation
import SwiftData

@Model
final class Ingredient {
    var name: String
    var amount: Double
    var unit: String
    var calories: Double
    var proteins: Double
    var fats: Double
    var carbs: Double

    var mealEvent: MealEvent?

    init(
        name: String,
        amount: Double,
        unit: String,
        calories: Double = 0,
        proteins: Double = 0,
        fats: Double = 0,
        carbs: Double = 0
    ) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.calories = calories
        self.proteins = proteins
        self.fats = fats
        self.carbs = carbs
    }
}
