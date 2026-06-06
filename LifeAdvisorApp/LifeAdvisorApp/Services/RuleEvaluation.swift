import Foundation

enum RuleZone: String, Comparable, CaseIterable {
    case normal = "normal"
    case violation = "violation"
    case noData = "no_data"

    static func < (lhs: RuleZone, rhs: RuleZone) -> Bool {
        order(lhs) < order(rhs)
    }

    static func worst(_ a: RuleZone, _ b: RuleZone) -> RuleZone {
        order(a) >= order(b) ? a : b
    }

    private static func order(_ zone: RuleZone) -> Int {
        switch zone {
        case .normal: return 0
        case .noData: return 1
        case .violation: return 2
        }
    }
}

struct EvaluationResult {
    let zone: RuleZone
    let magnitude: Double
    let reasonCode: String

    init(zone: RuleZone, magnitude: Double = 0, reasonCode: String = "") {
        self.zone = zone
        self.magnitude = magnitude
        self.reasonCode = reasonCode
    }

    static let noData = EvaluationResult(zone: .noData, reasonCode: "no_data")
}

func evaluateRange(
    value: Double,
    lower: Double?,
    upper: Double?
) -> EvaluationResult {
    if lower == nil && upper == nil {
        return EvaluationResult(zone: .normal, reasonCode: "no_bounds")
    }

    if let upper = upper, value > upper {
        return EvaluationResult(zone: .violation, magnitude: value - upper, reasonCode: "exceeds_upper")
    }
    if let lower = lower, value < lower {
        return EvaluationResult(zone: .violation, magnitude: lower - value, reasonCode: "below_lower")
    }

    return EvaluationResult(zone: .normal, reasonCode: "in_range")
}

func evaluatePresence(
    dailyItems: [EstimateItem],
    targetCategories: [String],
    inverse: Bool
) -> EvaluationResult {
    let anyMatch = dailyItems.contains { item in
        guard let category = item.foodCategory else { return false }
        return targetCategories.contains(category)
    }

    if inverse {
        // Inverse presence: violation if category IS present (e.g., processed meat)
        if anyMatch {
            return EvaluationResult(zone: .violation, magnitude: 1, reasonCode: "unwanted_category_present")
        }
        return EvaluationResult(zone: .normal, reasonCode: "unwanted_category_absent")
    }

    // Normal presence: violation if category NOT present
    if anyMatch {
        return EvaluationResult(zone: .normal, reasonCode: "category_present")
    }
    return EvaluationResult(zone: .violation, magnitude: 1, reasonCode: "category_missing")
}

func evaluateCountSkipped(
    skippedCount: Int,
    violationThreshold: Int
) -> EvaluationResult {
    if skippedCount >= violationThreshold {
        return EvaluationResult(
            zone: .violation,
            magnitude: Double(skippedCount),
            reasonCode: "excessive_skips"
        )
    }
    return EvaluationResult(zone: .normal, reasonCode: "regular")
}
