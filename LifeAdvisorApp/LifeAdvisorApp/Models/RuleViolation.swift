import Foundation
import SwiftData

@Model
final class RuleViolation {
    var ruleId: String
    var date: Date
    var zone: String
    var magnitude: Double
    var reasonCode: String
    var contributionJSON: String?

    @Relationship var mealEvent: MealEvent?
    @Relationship var estimateItem: EstimateItem?

    init(
        ruleId: String,
        date: Date,
        zone: String,
        magnitude: Double = 0,
        reasonCode: String = "",
        contributionJSON: String? = nil,
        mealEvent: MealEvent? = nil,
        estimateItem: EstimateItem? = nil
    ) {
        self.ruleId = ruleId
        self.date = date
        self.zone = zone
        self.magnitude = magnitude
        self.reasonCode = reasonCode
        self.contributionJSON = contributionJSON
        self.mealEvent = mealEvent
        self.estimateItem = estimateItem
    }
}
