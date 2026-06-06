import Foundation
import SwiftData

@Model
final class RuleContributionSnapshot {
    var ruleId: String
    var date: Date
    var zone: String
    var valueFormatted: String
    var thresholdFormatted: String
    var unit: String
    var field: String?

    @Relationship(deleteRule: .cascade, inverse: \RuleContributionItem.snapshot)
    var items: [RuleContributionItem] = []

    init(
        ruleId: String,
        date: Date,
        zone: String,
        valueFormatted: String,
        thresholdFormatted: String,
        unit: String,
        field: String? = nil
    ) {
        self.ruleId = ruleId
        self.date = date
        self.zone = zone
        self.valueFormatted = valueFormatted
        self.thresholdFormatted = thresholdFormatted
        self.unit = unit
        self.field = field
    }
}
