import Foundation
import SwiftData

@Model
final class MealTemplate {
    @Attribute(.unique) var name: String

    @Relationship(deleteRule: .cascade, inverse: \TemplateIngredient.template)
    var ingredients: [TemplateIngredient] = []

    init(name: String) {
        self.name = name
    }
}

@Model
final class TemplateIngredient {
    var name: String
    var amount: Double
    var unit: String
    var calories: Double
    var proteins: Double
    var fats: Double
    var carbs: Double

    var template: MealTemplate?

    init(
        name: String,
        amount: Double,
        unit: String,
        calories: Double,
        proteins: Double,
        fats: Double,
        carbs: Double
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
