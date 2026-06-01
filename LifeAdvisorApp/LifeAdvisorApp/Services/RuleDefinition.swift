import Foundation

struct RuleDefinition: Codable, Identifiable {
    let id: String
    let type: String
    let field: String?
    let params: RuleParams
    let warningRatio: Double
    let category: String
    let title: String
    let description: String
    let window: String
    let minDaysData: Int

    var categoryTitle: String {
        switch category {
        case "macronutrient_balance": return "Баланс макронутриентов"
        case "restrictions": return "Ограничения"
        case "food_quality": return "Качество продуктов"
        case "eating_pattern": return "Режим питания"
        default: return category
        }
    }
}

struct RuleParams: Codable {
    let lower: Double?
    let upper: Double?
    let category: String?
    let inverse: Bool?
    let warningThreshold: Double?
    let violationThreshold: Double?

    init(
        lower: Double? = nil,
        upper: Double? = nil,
        category: String? = nil,
        inverse: Bool? = nil,
        warningThreshold: Double? = nil,
        violationThreshold: Double? = nil
    ) {
        self.lower = lower
        self.upper = upper
        self.category = category
        self.inverse = inverse
        self.warningThreshold = warningThreshold
        self.violationThreshold = violationThreshold
    }
}

struct RulesFile: Codable {
    let rules: [RuleDefinition]
}
