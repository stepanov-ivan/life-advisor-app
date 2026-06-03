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
    var sourceModeRaw: String
    var grams: Double
    var baseGrams: Double
    var baseCalories: Double
    var baseProteins: Double
    var baseFats: Double
    var baseCarbs: Double
    var macrosLocked: Bool
    var estimatedSaturatedFats: Double
    var estimatedSugar: Double
    var estimatedFiber: Double
    var estimatedSodium: Double
    var foodCategory: String?

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
        sourceMode: EstimateSourceMode,
        grams: Double = 100,
        estimatedSaturatedFats: Double = 0,
        estimatedSugar: Double = 0,
        estimatedFiber: Double = 0,
        estimatedSodium: Double = 0,
        foodCategory: String? = nil
    ) {
        self.name = name
        self.estimatedCalories = estimatedCalories
        self.estimatedProteins = estimatedProteins
        self.estimatedFats = estimatedFats
        self.estimatedCarbs = estimatedCarbs
        self.impactScore = min(1, max(0, impactScore))
        self.reason = String(reason.prefix(140))
        self.sourceModeRaw = sourceMode.rawValue
        self.grams = max(0, grams)
        self.baseGrams = max(0.1, grams)
        self.baseCalories = estimatedCalories
        self.baseProteins = estimatedProteins
        self.baseFats = estimatedFats
        self.baseCarbs = estimatedCarbs
        self.macrosLocked = false
        self.estimatedSaturatedFats = estimatedSaturatedFats
        self.estimatedSugar = estimatedSugar
        self.estimatedFiber = estimatedFiber
        self.estimatedSodium = estimatedSodium
        self.foodCategory = foodCategory
    }
}
