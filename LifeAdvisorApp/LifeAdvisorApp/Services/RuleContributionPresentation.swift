import Foundation

struct RuleContributionPresentation {
    static let percentFields: Set<String> = [
        "fatPercent",
        "saturatedFatPercent",
        "transFatPercent",
        "proteinPercent",
        "carbsPercent",
        "sugarPercent",
        "pufaPercent",
        "energyBalancePercent"
    ]

    static func isPercentField(_ field: String?) -> Bool {
        guard let field else { return false }
        return percentFields.contains(field)
    }

    static func contributionText(
        absoluteContribution: Double,
        percentContribution: Double,
        field: String?,
        language: AppLanguage
    ) -> String {
        if isPercentField(field) {
            return String(format: "%.1f%%", absoluteContribution * 100)
        }

        let unit = language == .ru ? "г" : "g"
        return "\(Int(absoluteContribution.rounded())) \(unit) (\(Int(percentContribution.rounded()))%)"
    }

    static func summaryHeader(
        for rule: RuleDefinition,
        localizer: RulePresentationLocalizer,
        language: AppLanguage
    ) -> String {
        let subject = summarySubject(for: rule, localizer: localizer)
        switch language {
        case .system:
            return "\(subject.capitalized) sources for the day"
        case .ru:
            return "Источники \(subject) за день"
        case .en:
            return "\(subject.capitalized) sources for the day"
        }
    }

    static func normText(for rule: RuleDefinition, language: AppLanguage) -> String {
        switch rule.type {
        case "presence":
            let inverse = rule.params.inverse ?? false
            switch (language, inverse) {
            case (.system, false): return "Target: present in the day's intake"
            case (.system, true): return "Target: absent from the day's intake"
            case (.ru, false): return "Норма: присутствует в рационе за день"
            case (.ru, true): return "Норма: отсутствует в рационе за день"
            case (.en, false): return "Target: present in the day's intake"
            case (.en, true): return "Target: absent from the day's intake"
            }
        case "range":
            let format = metricFormat(for: rule.field, language: language)
            let decimals = format.decimals
            switch (rule.params.lower, rule.params.upper) {
            case let (lower?, upper?):
                let lowerText = String(format: "%.\(decimals)f", lower * format.multiply)
                let upperText = String(format: "%.\(decimals)f", upper * format.multiply)
                if language == .ru {
                    return "Норма: \(lowerText)–\(upperText)\(format.unit)"
                }
                return "Target: \(lowerText)–\(upperText)\(format.unit)"
            case let (lower?, nil):
                let lowerText = String(format: "%.\(decimals)f", lower * format.multiply)
                if language == .ru {
                    return "Норма: не менее \(lowerText)\(format.unit)"
                }
                return "Target: at least \(lowerText)\(format.unit)"
            case let (nil, upper?):
                let upperText = String(format: "%.\(decimals)f", upper * format.multiply)
                if language == .ru {
                    return "Норма: не более \(upperText)\(format.unit)"
                }
                return "Target: at most \(upperText)\(format.unit)"
            case (nil, nil):
                return ""
            }
        default:
            return ""
        }
    }

    private static func summarySubject(
        for rule: RuleDefinition,
        localizer: RulePresentationLocalizer
    ) -> String {
        switch rule.field {
        case "proteinPercent":
            return localizer.language == .ru ? "белка" : "protein"
        case "fatPercent":
            return localizer.language == .ru ? "жиров" : "fat"
        case "saturatedFatPercent":
            return localizer.language == .ru ? "насыщенных жиров" : "saturated fat"
        case "carbsPercent":
            return localizer.language == .ru ? "углеводов" : "carbohydrates"
        case "sugarPercent":
            return localizer.language == .ru ? "сахара" : "sugar"
        case "fiberGrams":
            return localizer.language == .ru ? "клетчатки" : "fiber"
        case "fruitVegGrams":
            return localizer.language == .ru ? "овощей и фруктов" : "fruits and vegetables"
        case "redMeatGrams":
            return localizer.language == .ru ? "красного мяса" : "red meat"
        case "sodiumMg":
            return localizer.language == .ru ? "натрия" : "sodium"
        default:
            if rule.type == "presence", let category = rule.params.category {
                return localizer.categoryName(for: "category_\(category)")
            }
            return localizer.ruleTitle(for: rule.id).lowercased()
        }
    }

    private struct MetricFormat {
        let unit: String
        let multiply: Double
        let decimals: Int
    }

    private static func metricFormat(for field: String?, language: AppLanguage) -> MetricFormat {
        guard let field else {
            return MetricFormat(unit: "", multiply: 1, decimals: 0)
        }

        let gramsUnit = language == .ru ? " г" : " g"
        let milligramsUnit = language == .ru ? " мг" : " mg"

        switch field {
        case "fatPercent", "proteinPercent", "carbsPercent",
             "saturatedFatPercent", "transFatPercent", "sugarPercent",
             "energyBalancePercent", "pufaPercent":
            return MetricFormat(unit: "%", multiply: 100, decimals: 1)
        case "sodiumMg":
            return MetricFormat(unit: milligramsUnit, multiply: 1, decimals: 0)
        case "fiberGrams", "fruitVegGrams", "redMeatGrams":
            return MetricFormat(unit: gramsUnit, multiply: 1, decimals: 0)
        default:
            return MetricFormat(unit: "", multiply: 1, decimals: 0)
        }
    }
}
