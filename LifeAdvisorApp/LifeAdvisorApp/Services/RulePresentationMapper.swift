import Foundation

enum ViolationPresentationCase {
    case exceedsUpper(ruleId: String, valueFormatted: String, thresholdFormatted: String)
    case belowLower(ruleId: String, valueFormatted: String, thresholdFormatted: String)
    case approachingUpper(ruleId: String, valueFormatted: String, thresholdFormatted: String)
    case approachingLower(ruleId: String, valueFormatted: String, thresholdFormatted: String)
    case categoryMissing(categoryId: String)
    case unwantedCategoryPresent(categoryId: String)
    case excessiveSkips(count: Int)
    case someSkips(count: Int)
}

struct RulePresentationMapper {
    let engine: RuleEngine

    func map(violation: RuleViolation) -> ViolationPresentationCase? {
        guard let rule = engine.allRules().first(where: { $0.id == violation.ruleId }) else {
            return nil
        }

        switch violation.reasonCode {
        case "exceeds_upper":
            let metric = engine.formattedMetric(for: rule, date: violation.date)
            return .exceedsUpper(ruleId: rule.id, valueFormatted: metric.valueFormatted, thresholdFormatted: metric.thresholdFormatted)
        case "below_lower":
            let metric = engine.formattedMetric(for: rule, date: violation.date)
            return .belowLower(ruleId: rule.id, valueFormatted: metric.valueFormatted, thresholdFormatted: metric.thresholdFormatted)
        case "approaching_upper":
            let metric = engine.formattedMetric(for: rule, date: violation.date)
            return .approachingUpper(ruleId: rule.id, valueFormatted: metric.valueFormatted, thresholdFormatted: metric.thresholdFormatted)
        case "approaching_lower":
            let metric = engine.formattedMetric(for: rule, date: violation.date)
            return .approachingLower(ruleId: rule.id, valueFormatted: metric.valueFormatted, thresholdFormatted: metric.thresholdFormatted)
        case "category_missing":
            return .categoryMissing(categoryId: rule.params.category ?? "unknown")
        case "unwanted_category_present":
            return .unwantedCategoryPresent(categoryId: rule.params.category ?? "unknown")
        case "excessive_skips":
            return .excessiveSkips(count: Int(violation.magnitude))
        case "some_skips":
            return .someSkips(count: Int(violation.magnitude))
        default:
            return nil
        }
    }
}
