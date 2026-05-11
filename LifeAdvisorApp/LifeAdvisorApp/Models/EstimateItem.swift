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
