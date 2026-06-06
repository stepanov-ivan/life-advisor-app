import SwiftUI
import SwiftData

struct DayAnalyticsPanel: View {
    let rules: [RuleDefinition]
    let engine: RuleEngine
    let date: Date
    @StateObject private var languageManager = AppLanguageManager.shared
    @State private var expandedRuleId: String?
    @State private var expandedTailRuleId: String?

    private var dayRules: [RuleDefinition] {
        rules.filter { rule in
            engine.isRuleEnabled(rule.id)
                && rule.window == "day"
                && ["range", "presence"].contains(rule.type)
        }
    }

    private var visibleDayRules: [RuleDefinition] {
        dayRules.filter { snapshotsById[$0.id] != nil }
    }

    private var groups: [RuleGroupingPolicy.Section] {
        RuleGroupingPolicy(language: languageManager.effectiveLanguage)
            .sections(for: visibleDayRules, surface: .dayAnalytics)
    }

    private var rulesById: [String: RuleDefinition] {
        Dictionary(uniqueKeysWithValues: visibleDayRules.map { ($0.id, $0) })
    }

    private var snapshotsById: [String: RuleContributionSnapshot] {
        let daySnapshots = engine.snapshotsForDay(date)
        return Dictionary(uniqueKeysWithValues: daySnapshots.map { ($0.ruleId, $0) })
    }

    private var summaryText: String {
        let visibleRules = groups.flatMap { $0.ruleIds.compactMap { rulesById[$0] } }
        let normalCount = visibleRules.filter { snapshotsById[$0.id]?.zone == RuleZone.normal.rawValue }.count
        let total = visibleRules.count
        let template = LocalizationHelper.localized("%d из %d правил соблюдаются", table: "Localizable", language: languageManager.effectiveLanguage)
        return String(format: template, normalCount, total)
    }

    private var worstZone: RuleZone {
        var worst: RuleZone = .normal
        for rule in groups.flatMap({ $0.ruleIds.compactMap { rulesById[$0] } }) {
            let zone = RuleZone(rawValue: snapshotsById[rule.id]?.zone ?? "") ?? .normal
            worst = RuleZone.worst(worst, zone)
        }
        return worst
    }

    var body: some View {
        if groups.isEmpty || visibleDayRules.isEmpty {
            VStack(spacing: 8) {
                Text(LocalizationHelper.localized("Нет данных за сегодня", table: "Localizable", language: languageManager.effectiveLanguage))
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
                Text(LocalizationHelper.localized("Правила питания", table: "Localizable", language: languageManager.effectiveLanguage))
                    .font(.headline)
                    .padding(.horizontal)

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
                                ruleRow(rule)
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

    // MARK: - Rule Row

    @ViewBuilder
    private func ruleRow(_ rule: RuleDefinition) -> some View {
        let metric = engine.formattedMetric(for: rule, date: date)
        let localizer = RulePresentationLocalizer(language: languageManager.effectiveLanguage)
        let isExpanded = expandedRuleId == rule.id
        let snapshot = snapshotsById[rule.id]
        let isExpandable = snapshot != nil

        VStack(spacing: 0) {
            if isExpandable {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded {
                            expandedRuleId = nil
                            expandedTailRuleId = nil
                        } else {
                            expandedRuleId = rule.id
                            expandedTailRuleId = nil
                        }
                    }
                } label: {
                    rowContent(metric: metric, localizer: localizer, rule: rule, isExpanded: isExpanded, showsDisclosure: true)
                }
                .buttonStyle(.plain)
            } else {
                rowContent(metric: metric, localizer: localizer, rule: rule, isExpanded: false, showsDisclosure: false)
            }

            if isExpanded, let snapshot = snapshot {
                expandedContent(snapshot: snapshot, rule: rule)
            }
        }
    }

    private func rowContent(
        metric: RuleEngine.RuleMetricDisplay,
        localizer: RulePresentationLocalizer,
        rule: RuleDefinition,
        isExpanded: Bool,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(zoneColor(metric.zone))
                .frame(width: 10, height: 10)

            Text(localizer.ruleTitle(for: rule.id))
                .font(.body)
                .foregroundColor(.primary)

            Spacer()

            if metric.zone == .noData {
                Text(languageManager.effectiveLanguage == .ru ? "Нет данных" : "No data")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text(metric.valueFormatted)
                    .font(.caption)
                    .foregroundColor(zoneColor(metric.zone))
            }

            if showsDisclosure {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private func expandedContent(snapshot: RuleContributionSnapshot, rule: RuleDefinition) -> some View {
        let items = snapshot.items.sorted {
            if $0.absoluteContribution == $1.absoluteContribution {
                return $0.dayOrderIndex < $1.dayOrderIndex
            }
            return $0.absoluteContribution > $1.absoluteContribution
        }
        let showAll = expandedTailRuleId == rule.id
        let localizer = RulePresentationLocalizer(language: languageManager.effectiveLanguage)

        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 4) {
                Text(RuleContributionPresentation.summaryHeader(
                    for: rule,
                    localizer: localizer,
                    language: languageManager.effectiveLanguage
                ))
                    .font(.subheadline.bold())
                HStack(spacing: 4) {
                    Text(snapshot.valueFormatted)
                        .foregroundColor(zoneColor(RuleZone(rawValue: snapshot.zone) ?? .normal))
                }
                .font(.subheadline)
                let normText = RuleContributionPresentation.normText(for: rule, language: languageManager.effectiveLanguage)
                if !normText.isEmpty {
                    Text(normText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            let visibleItems = showAll ? items : Array(items.prefix(3))
            if visibleItems.isEmpty {
                Text(languageManager.effectiveLanguage == .ru ? "Нет значимых источников за день" : "No contributing products for this day")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(visibleItems, id: \.persistentModelID) { item in
                    HStack(spacing: 8) {
                        Text(item.productName)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(RuleContributionPresentation.contributionText(
                            absoluteContribution: item.absoluteContribution,
                            percentContribution: item.percentContribution,
                            field: rule.field,
                            language: languageManager.effectiveLanguage
                        ))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
            }

            if items.count > 3 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedTailRuleId = showAll ? nil : rule.id
                    }
                } label: {
                    HStack {
                        Text(showAll
                             ? (languageManager.effectiveLanguage == .ru ? "Свернуть" : "Collapse")
                             : (languageManager.effectiveLanguage == .ru ? "Ещё \(items.count - 3) продукта" : "\(items.count - 3) more products"))
                            .font(.caption)
                        Spacer()
                        Image(systemName: showAll ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 8)
    }

    private func zoneColor(_ zone: RuleZone) -> Color {
        switch zone {
        case .normal: return .green
        case .violation: return .red
        case .noData: return .gray
        }
    }
}
