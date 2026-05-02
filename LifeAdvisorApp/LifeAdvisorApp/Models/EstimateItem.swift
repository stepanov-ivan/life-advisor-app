import Foundation
import SwiftData

@Model
final class EstimateItem {
    var name: String
    var estimatedCalories: Double
    var estimatedProteins: Double
    var estimatedFats: Double
    var estimatedCarbs: Double
    var impactScore: Double
    var reason: String
    var highCalorieFlag: Bool
    var sourceModeRaw: String

    var mealEvent: MealEvent?

    var sourceMode: EstimateSourceMode {
        get { EstimateSourceMode(rawValue: sourceModeRaw) ?? .compositeItem }
        set { sourceModeRaw = newValue.rawValue }
    }

    init(
        name: String,
        estimatedCalories: Double,
        estimatedProteins: Double,
        estimatedFats: Double,
        estimatedCarbs: Double,
        impactScore: Double,
        reason: String,
        highCalorieFlag: Bool,
        sourceMode: EstimateSourceMode
    ) {
        self.name = name
        self.estimatedCalories = estimatedCalories
        self.estimatedProteins = estimatedProteins
        self.estimatedFats = estimatedFats
        self.estimatedCarbs = estimatedCarbs
        self.impactScore = min(1, max(0, impactScore))
        self.reason = String(reason.prefix(140))
        self.highCalorieFlag = highCalorieFlag
        self.sourceModeRaw = sourceMode.rawValue
    }
}

@Model
final class EstimationMemory {
    @Attribute(.unique) var fingerprint: String
    var calories: Double
    var proteins: Double
    var fats: Double
    var carbs: Double
    var updatedAt: Date

    init(fingerprint: String, calories: Double, proteins: Double, fats: Double, carbs: Double, updatedAt: Date = Date()) {
        self.fingerprint = fingerprint
        self.calories = calories
        self.proteins = proteins
        self.fats = fats
        self.carbs = carbs
        self.updatedAt = updatedAt
    }
}
