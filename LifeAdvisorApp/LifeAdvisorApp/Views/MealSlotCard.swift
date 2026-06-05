import SwiftUI

struct MealSlotCard: View {
    let windowLabel: String
    let timeRange: String
    let event: MealEvent?
    let violations: [RuleViolation]
    let engine: RuleEngine
    let onTap: () -> Void
    @StateObject private var languageManager = AppLanguageManager.shared

    private struct ProductViolation {
        let ruleId: String
        let ruleTitle: String
        let percent: Double
        let zone: String
    }

    private var productViolationMap: [String: [ProductViolation]] {
        var map: [String: [ProductViolation]] = [:]
        for violation in violations {
            // Пропускаем below_lower и approaching_lower — продукты не виноваты в недостатке
            guard !["below_lower", "approaching_lower"].contains(violation.reasonCode) else { continue }
            guard let json = violation.contributionJSON,
                  let data = json.data(using: .utf8),
                  let entries = try? JSONDecoder().decode([RuleEngine.ContributionEntry].self, from: data) else {
                continue
            }
            let localizer = RulePresentationLocalizer(language: languageManager.effectiveLanguage)
            let ruleTitle = engine.allRules().first(where: { $0.id == violation.ruleId }).map { localizer.ruleTitle(for: $0.id) } ?? violation.ruleId
            for entry in entries {
                let pv = ProductViolation(
                    ruleId: violation.ruleId,
                    ruleTitle: ruleTitle,
                    percent: entry.percent,
                    zone: violation.zone
                )
                map[entry.itemId, default: []].append(pv)
            }
        }
        return map
    }

    private func maxContributionPercent(for violation: RuleViolation) -> Double {
        guard let json = violation.contributionJSON,
              let data = json.data(using: .utf8),
              let entries = try? JSONDecoder().decode([RuleEngine.ContributionEntry].self, from: data) else {
            return 0
        }
        return entries.map(\.percent).max() ?? 0
    }

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
                    Label("Пропущено", systemImage: "slash.circle")
                        .foregroundColor(.secondary)
                case .pendingEstimation:
                    Label(event.rawText ?? "Оценка...", systemImage: "clock")
                        .foregroundColor(.orange)
                case .parseFailed:
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.rawText ?? "")
                        Text("Последняя оценка не обновлена")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                case .structured:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(event.calories)) ккал").font(.title3.bold())
                        Text(String(format: LocalizationHelper.localized("meal_macros_format", table: "Localizable", language: languageManager.effectiveLanguage), Int(event.proteins), Int(event.fats), Int(event.carbs)))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(event.estimateItems.prefix(5), id: \.persistentModelID) { item in
                            let itemId = item.persistentModelID.storeIdentifier ?? ""
                            let itemViolations = productViolationMap[itemId]

                            if let itemViols = itemViolations, !itemViols.isEmpty {
                                let worstZone = itemViols.map(\.zone).contains("violation") ? "violation" : "warning"
                                let zoneColor = worstZone == "violation" ? Color.red : Color.yellow

                                DisclosureGroup {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(itemViols, id: \.ruleId) { pv in
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(pv.zone == "violation" ? Color.red : Color.yellow)
                                                    .frame(width: 5, height: 5)
                                                Text(String(format: LocalizationHelper.localized("product_contribution_format", table: "Localizable", language: languageManager.effectiveLanguage), pv.ruleTitle, Int(pv.percent)))
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
                                            .fill(zoneColor)
                                            .frame(width: 6, height: 6)
                                        Text(item.name).font(.caption)
                                        Spacer()
                                        Text("\(Int(item.estimatedCalories)) ккал").font(.caption2)
                                    }
                                    .foregroundColor(.secondary)
                                }
                            } else {
                                HStack {
                                    Text(item.name).font(.caption)
                                    Spacer()
                                    Text("\(Int(item.estimatedCalories)) ккал").font(.caption2)
                                }
                                .foregroundColor(.secondary)
                            }
                        }

                        let relevantViolations = violations.filter {
                            ["exceeds_upper", "approaching_upper", "unwanted_category_present"].contains($0.reasonCode)
                        }
                        if !relevantViolations.isEmpty {
                            Divider()
                            ForEach(relevantViolations.prefix(3)) { violation in
                                let desc = engine.violationDescription(for: violation)
                                HStack(alignment: .top, spacing: 4) {
                                    Circle()
                                        .fill(violation.zone == "violation" ? Color.red : Color.yellow)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 5)
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundColor(violation.zone == "violation" ? .red : .yellow)
                                }
                            }
                        }
                    }
                case .empty:
                    EmptyView()
                }
            } else {
                Label("Записать приём пищи", systemImage: "plus.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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
