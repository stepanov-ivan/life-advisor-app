import SwiftUI

struct DayAnalyticsPanel: View {
    let rules: [RuleDefinition]
    let engine: RuleEngine
    let date: Date
    @StateObject private var languageManager = AppLanguageManager.shared

    private struct CategoryGroup: Identifiable {
        let id: String
        let title: String
        let ruleIds: [String]
    }

    private var groups: [CategoryGroup] {
        let enabled = rules.filter { engine.isRuleEnabled($0.id) }
        return RuleGroupingPolicy(language: languageManager.effectiveLanguage)
            .sections(for: enabled, surface: .dayAnalytics)
            .map { CategoryGroup(id: $0.id, title: $0.title, ruleIds: $0.ruleIds) }
    }

    private var rulesById: [String: RuleDefinition] {
        Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
    }

    private var summaryText: String {
        let visibleRules = groups.flatMap { $0.ruleIds.compactMap { rulesById[$0] } }
        let normalCount = visibleRules.filter { engine.evaluateRule($0, for: date).zone == .normal }.count
        let total = visibleRules.count
        let template = LocalizationHelper.localized("%d из %d правил соблюдаются", table: "Localizable", language: languageManager.effectiveLanguage)
        return String(format: template, normalCount, total)
    }

    private var worstZone: RuleZone {
        var worst: RuleZone = .normal
        for rule in groups.flatMap({ $0.ruleIds.compactMap { rulesById[$0] } }) {
            let zone = engine.evaluateRule(rule, for: date).zone
            worst = RuleZone.worst(worst, zone)
        }
        return worst
    }

    var body: some View {
        if groups.isEmpty {
            VStack(spacing: 8) {
                Text("Нет данных за сегодня")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(12)
            .padding(.horizontal)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Правила питания")
                    .font(.headline)
                    .padding(.horizontal)

                // Summary line
                Text(summaryText)
                    .font(.subheadline.bold())
                    .foregroundColor(zoneColor(worstZone))
                    .padding(.horizontal)

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(group.ruleIds, id: \.self) { ruleId in
                            if let rule = rulesById[ruleId] {
                                let metric = engine.formattedMetric(for: rule, date: date)
                                let localizer = RulePresentationLocalizer(language: languageManager.effectiveLanguage)
                                NavigationLink {
                                    RuleDetailView(
                                        rule: rule,
                                        selectedDate: .constant(date),
                                        selectedTab: .constant(1)
                                    )
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle()
                                            .fill(zoneColor(metric.zone))
                                            .frame(width: 10, height: 10)

                                        Text(localizer.ruleTitle(for: rule.id))
                                            .font(.body)
                                            .foregroundColor(.primary)

                                        Spacer()

                                        if metric.zone == .noData {
                                            Text("Нет данных")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        } else if rule.type == "presence" {
                                            Text(metric.valueFormatted)
                                                .font(.caption)
                                                .foregroundColor(zoneColor(metric.zone))
                                        } else {
                                            Text(String(format: LocalizationHelper.localized("%@ из %@", table: "Localizable", language: languageManager.effectiveLanguage), metric.valueFormatted, metric.thresholdFormatted))
                                                .font(.caption)
                                                .foregroundColor(zoneColor(metric.zone))
                                        }
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    if group.id != groups.last?.id {
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    private func zoneColor(_ zone: RuleZone) -> Color {
        switch zone {
        case .normal: return .green
        case .warning: return .yellow
        case .violation: return .red
        case .noData: return .gray
        }
    }
}
