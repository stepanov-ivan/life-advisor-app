import SwiftUI
import SwiftData

struct MealSlotCard: View {
    let windowLabel: String
    let timeRange: String
    let event: MealEvent?
    let engine: RuleEngine
    let onTap: () -> Void
    @StateObject private var languageManager = AppLanguageManager.shared
    @State private var expandedItemId: PersistentIdentifier?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(windowLabel).font(.headline)
                Spacer()
                Text(timeRange).font(.caption).foregroundColor(.secondary)
            }

            if let event {
                switch event.status {
                case .skipped:
                    Label(LocalizationHelper.localized("Пропущено", table: "Localizable", language: languageManager.effectiveLanguage), systemImage: "slash.circle")
                        .foregroundColor(.secondary)
                case .pendingEstimation:
                    Label(event.rawText ?? LocalizationHelper.localized("Оценка...", table: "Localizable", language: languageManager.effectiveLanguage), systemImage: "clock")
                        .foregroundColor(.orange)
                case .parseFailed:
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.rawText ?? "")
                        Text(LocalizationHelper.localized("Последняя оценка не обновлена", table: "Localizable", language: languageManager.effectiveLanguage))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                case .structured:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(event.calories)) \(LocalizationHelper.localized("ккал", table: "Localizable", language: languageManager.effectiveLanguage))").font(.title3.bold())
                        Text(String(format: LocalizationHelper.localized("meal_macros_format", table: "Localizable", language: languageManager.effectiveLanguage), Int(event.proteins), Int(event.fats), Int(event.carbs)))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(event.estimateItems.prefix(5), id: \.persistentModelID) { item in
                            let sigViolations = engine.significantViolationsForItem(item, date: event.timestamp)

                            if !sigViolations.isEmpty {
                                DisclosureGroup(isExpanded: Binding(
                                    get: { expandedItemId == item.persistentModelID },
                                    set: { expandedItemId = $0 ? item.persistentModelID : nil }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(sigViolations, id: \.ruleId) { contrib in
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(Color.red)
                                                    .frame(width: 5, height: 5)
                                                let localizer = RulePresentationLocalizer(language: languageManager.effectiveLanguage)
                                                let rule = engine.allRules().first(where: { $0.id == contrib.ruleId })
                                                let title = rule.map { localizer.ruleTitle(for: $0.id) } ?? contrib.ruleId
                                                Text("\(title) \(contributionFormat(for: contrib, rule: rule))")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.leading, 12)
                                    .padding(.top, 2)
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 6, height: 6)
                                        Text(item.name).font(.caption)
                                        Spacer()
                                        Text("\(Int(item.estimatedCalories)) \(LocalizationHelper.localized("ккал", table: "Localizable", language: languageManager.effectiveLanguage))").font(.caption2)
                                    }
                                    .foregroundColor(.secondary)
                                }
                            } else {
                                HStack {
                                    Text(item.name).font(.caption)
                                    Spacer()
                                    Text("\(Int(item.estimatedCalories)) \(LocalizationHelper.localized("ккал", table: "Localizable", language: languageManager.effectiveLanguage))").font(.caption2)
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                case .empty:
                    EmptyView()
                }
            } else {
                Label(LocalizationHelper.localized("Записать приём пищи", table: "Localizable", language: languageManager.effectiveLanguage), systemImage: "plus.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func contributionFormat(for item: RuleContributionItem, rule: RuleDefinition?) -> String {
        RuleContributionPresentation.contributionText(
            absoluteContribution: item.absoluteContribution,
            percentContribution: item.percentContribution,
            field: rule?.field,
            language: languageManager.effectiveLanguage
        )
    }

    private var backgroundColor: Color {
        guard let event else { return Color.gray.opacity(0.15) }
        switch event.status {
        case .empty: return Color.gray.opacity(0.15)
        case .pendingEstimation: return Color.yellow.opacity(0.2)
        case .structured: return Color.green.opacity(0.2)
        case .parseFailed: return Color.orange.opacity(0.2)
        case .skipped: return Color.gray.opacity(0.15)
        }
    }
}
