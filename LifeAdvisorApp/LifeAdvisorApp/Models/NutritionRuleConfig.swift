import Foundation
import SwiftData

@Model
final class NutritionRuleConfig {
    var ruleId: String
    var isEnabled: Bool

    init(ruleId: String, isEnabled: Bool = true) {
        self.ruleId = ruleId
        self.isEnabled = isEnabled
    }
}
