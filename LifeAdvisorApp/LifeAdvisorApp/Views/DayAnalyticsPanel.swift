import SwiftUI

struct DayAnalyticsPanel: View {
    let rules: [RuleDefinition]
    let engine: RuleEngine
    let date: Date

    private struct CategoryGroup: Identifiable {
        let id: String
        let title: String
        let rules: [RuleDefinition]
    }

    private var groups: [CategoryGroup] {
        let enabled = rules.filter { engine.isRuleEnabled($0.id) }
        let macros = enabled.filter { $0.category == "macronutrient_balance" }
        let restrictions = enabled.filter { $0.category == "restrictions" }
        let qualityAndPattern = enabled.filter { $0.category == "food_quality" || $0.category == "eating_pattern" }

        return [
            CategoryGroup(id: "macros", title: "Баланс макронутриентов", rules: macros),
            CategoryGroup(id: "restrictions", title: "Ограничения", rules: restrictions),
            CategoryGroup(id: "quality", title: "Качество продуктов и режим", rules: qualityAndPattern)
        ].filter { !$0.rules.isEmpty }
    }

    private var summaryText: String {
        let normalCount = groups.flatMap { $0.rules }.filter {
            engine.evaluateRule($0, for: date).zone == .normal
        }.count
        let total = groups.flatMap { $0.rules }.count
        return "\(normalCount) из \(total) правил соблюдаются"
    }

    private var worstZone: RuleZone {
        var worst: RuleZone = .normal
        for rule in groups.flatMap({ $0.rules }) {
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

                        ForEach(group.rules) { rule in
                            let metric = engine.formattedMetric(for: rule, date: date)
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

                                    Text(rule.title)
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
                                        Text("\(metric.valueFormatted) из \(metric.thresholdFormatted)")
                                            .font(.caption)
                                            .foregroundColor(zoneColor(metric.zone))
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 6)
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
