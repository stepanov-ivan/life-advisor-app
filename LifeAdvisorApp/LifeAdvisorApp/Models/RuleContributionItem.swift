import Foundation
import SwiftData

@Model
final class RuleContributionItem {
    var ruleId: String
    var productName: String
    var absoluteContribution: Double
    var percentContribution: Double
    var dayOrderIndex: Int

    @Relationship var snapshot: RuleContributionSnapshot?
    @Relationship var mealEvent: MealEvent?
    @Relationship var estimateItem: EstimateItem?

    init(
        ruleId: String,
        productName: String,
        absoluteContribution: Double,
        percentContribution: Double,
        dayOrderIndex: Int = 0,
        snapshot: RuleContributionSnapshot? = nil,
        mealEvent: MealEvent? = nil,
        estimateItem: EstimateItem? = nil
    ) {
        self.ruleId = ruleId
        self.productName = productName
        self.absoluteContribution = absoluteContribution
        self.percentContribution = percentContribution
        self.dayOrderIndex = dayOrderIndex
        self.snapshot = snapshot
        self.mealEvent = mealEvent
        self.estimateItem = estimateItem
    }
}
