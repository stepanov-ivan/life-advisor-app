import Foundation

struct RuleGroupingPolicy {
    let language: AppLanguage

    enum Surface {
        case rulesList
        case dayAnalytics
    }

    struct Section: Identifiable {
        let id: String
        let title: String
        let ruleIds: [String]
    }

    func sections(for rules: [RuleDefinition], surface: Surface) -> [Section] {
        let macros = rules.filter { $0.category == "macronutrient_balance" }
        let restrictions = rules.filter { $0.category == "restrictions" }
        let quality = rules.filter { $0.category == "food_quality" }
        let pattern = rules.filter { $0.category == "eating_pattern" }
        let qualityAndPattern = rules.filter { $0.category == "food_quality" || $0.category == "eating_pattern" }

        let localizer = RulePresentationLocalizer(language: language)

        var result: [Section] = []
        if !macros.isEmpty {
            result.append(Section(
                id: "section_macros",
                title: localizer.sectionTitle(for: "section_macros"),
                ruleIds: macros.map { $0.id }
            ))
        }
        if !restrictions.isEmpty {
            result.append(Section(
                id: "section_restrictions",
                title: localizer.sectionTitle(for: "section_restrictions"),
                ruleIds: restrictions.map { $0.id }
            ))
        }
        switch surface {
        case .rulesList:
            if !quality.isEmpty {
                result.append(Section(
                    id: "food_quality",
                    title: localizer.categoryName(for: "food_quality"),
                    ruleIds: quality.map { $0.id }
                ))
            }
            if !pattern.isEmpty {
                result.append(Section(
                    id: "eating_pattern",
                    title: localizer.categoryName(for: "eating_pattern"),
                    ruleIds: pattern.map { $0.id }
                ))
            }
        case .dayAnalytics:
            if !qualityAndPattern.isEmpty {
                result.append(Section(
                    id: "section_quality_pattern",
                    title: localizer.sectionTitle(for: "section_quality_pattern"),
                    ruleIds: qualityAndPattern.map { $0.id }
                ))
            }
        }
        return result
    }
}
