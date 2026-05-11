import Foundation
import SwiftData

enum MeasureUnit: String, Codable, CaseIterable {
    case g
    case ml
    case pcs

    var title: String {
        switch self {
        case .g: return "г"
        case .ml: return "мл"
        case .pcs: return "шт"
        }
    }
}

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
    var quantity: Double
    var unitRaw: String
    var baseCalories: Double
    var baseProteins: Double
    var baseFats: Double
    var baseCarbs: Double
    var macrosLocked: Bool

    var mealEvent: MealEvent?

    var sourceMode: EstimateSourceMode {
        get { EstimateSourceMode(rawValue: sourceModeRaw) ?? .compositeItem }
        set { sourceModeRaw = newValue.rawValue }
    }

    var unit: MeasureUnit {
        get { MeasureUnit(rawValue: unitRaw) ?? .g }
        set { unitRaw = newValue.rawValue }
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
        sourceMode: EstimateSourceMode,
        quantity: Double = 100,
        unit: MeasureUnit = .g
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
        self.quantity = max(0, quantity)
        self.unitRaw = unit.rawValue
        self.baseCalories = estimatedCalories
        self.baseProteins = estimatedProteins
        self.baseFats = estimatedFats
        self.baseCarbs = estimatedCarbs
        self.macrosLocked = false
    }
}
