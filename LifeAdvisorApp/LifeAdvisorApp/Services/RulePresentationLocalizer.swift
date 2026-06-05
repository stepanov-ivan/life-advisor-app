import Foundation

struct RulePresentationLocalizer {
    let language: AppLanguage

    func ruleTitle(for ruleId: String) -> String {
        LocalizationHelper.localized(ruleId, table: "Rules", language: language)
    }

    func ruleDescription(for ruleId: String) -> String {
        LocalizationHelper.localized("\(ruleId)_desc", table: "Rules", language: language)
    }

    func categoryName(for categoryId: String) -> String {
        LocalizationHelper.localized(categoryId, table: "Rules", language: language)
    }

    func sectionTitle(for sectionId: String) -> String {
        LocalizationHelper.localized(sectionId, table: "Rules", language: language)
    }

    func localizedDescription(for violationCase: ViolationPresentationCase) -> String {
        switch violationCase {
        case let .exceedsUpper(ruleId, valueFormatted, thresholdFormatted):
            let title = ruleTitle(for: ruleId)
            let template = LocalizationHelper.localized("exceeds_upper", table: "Rules", language: language)
            return String(format: template, title, valueFormatted, thresholdFormatted)
        case let .belowLower(ruleId, valueFormatted, thresholdFormatted):
            let title = ruleTitle(for: ruleId)
            let template = LocalizationHelper.localized("below_lower", table: "Rules", language: language)
            return String(format: template, title, valueFormatted, thresholdFormatted)
        case let .approachingUpper(ruleId, valueFormatted, thresholdFormatted):
            let title = ruleTitle(for: ruleId)
            let template = LocalizationHelper.localized("approaching_upper", table: "Rules", language: language)
            return String(format: template, title, valueFormatted, thresholdFormatted)
        case let .approachingLower(ruleId, valueFormatted, thresholdFormatted):
            let title = ruleTitle(for: ruleId)
            let template = LocalizationHelper.localized("approaching_lower", table: "Rules", language: language)
            return String(format: template, title, valueFormatted, thresholdFormatted)
        case let .categoryMissing(categoryId):
            let title = categoryName(for: "category_\(categoryId)")
            let template = LocalizationHelper.localized("category_missing", table: "Rules", language: language)
            return String(format: template, title)
        case let .unwantedCategoryPresent(categoryId):
            let title = categoryName(for: "category_\(categoryId)")
            let template = LocalizationHelper.localized("unwanted_category_present", table: "Rules", language: language)
            return String(format: template, title)
        case let .excessiveSkips(count):
            return String(format: LocalizationHelper.localized("excessive_skips", table: "Rules", language: language), count)
        case let .someSkips(count):
            return String(format: LocalizationHelper.localized("some_skips", table: "Rules", language: language), count)
        }
    }

    func localizedDescription(for violation: RuleViolation, engine: RuleEngine) -> String {
        let mapper = RulePresentationMapper(engine: engine)
        guard let case_ = mapper.map(violation: violation) else {
            return LocalizationHelper.localized(violation.reasonCode, table: "Rules", language: language)
        }
        return localizedDescription(for: case_)
    }
}
