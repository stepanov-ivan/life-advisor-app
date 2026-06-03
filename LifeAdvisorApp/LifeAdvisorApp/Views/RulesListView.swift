import SwiftUI
import SwiftData

struct RulesListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var engine = RuleEngine()

    var body: some View {
        NavigationStack {
            Group {
                if let error = engine.loadError {
                    ContentUnavailableView(
                        "Ошибка загрузки правил",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    rulesList
                }
            }
            .navigationTitle("Правила")
            .onAppear {
                engine.configure(context: modelContext)
                engine.resetWeekIfNeeded()
                engine.fullRebuild(for: engine.bestEvaluationDate())
            }
        }
    }

    private var rulesList: some View {
        let summary = engine.summary(date: Date())
        let allRules = engine.allRules()
        let grouped = Dictionary(grouping: allRules) { $0.categoryTitle }

        return List {
            // Summary
            Section {
                HStack {
                    Text("\(summary.normal) из \(summary.total) правил соблюдаются")
                        .font(.headline)
                    Spacer()
                    summaryCircle(normal: summary.normal, total: summary.total)
                }
                .padding(.vertical, 4)
            }

            // Rule sections
            ForEach(["Баланс макронутриентов", "Ограничения", "Качество продуктов", "Режим питания"], id: \.self) { category in
                if let rules = grouped[category] {
                    Section(category) {
                        ForEach(rules) { rule in
                            ruleRow(rule)
                        }
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: RuleDefinition) -> some View {
        let result = engine.evaluateToday(rule: rule)
        let enabled = engine.isRuleEnabled(rule.id)

        return HStack(spacing: 12) {
            zoneIndicator(result.zone)
                .opacity(enabled ? 1 : 0.3)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.title)
                    .font(.body)
                    .foregroundColor(enabled ? .primary : .secondary)
                Text(rule.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !enabled {
                Text("Выкл")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(zoneLabel(result.zone))
                    .font(.caption)
                    .foregroundColor(zoneColor(result.zone))
            }

            Toggle("", isOn: Binding(
                get: { engine.isRuleEnabled(rule.id) },
                set: { engine.setRuleEnabled(rule.id, enabled: $0) }
            ))
            .labelsHidden()
        }
    }

    private func zoneIndicator(_ zone: RuleZone) -> some View {
        Circle()
            .fill(zoneColor(zone))
            .frame(width: 10, height: 10)
    }

    private func zoneColor(_ zone: RuleZone) -> Color {
        switch zone {
        case .normal: return .green
        case .warning: return .yellow
        case .violation: return .red
        case .noData: return .gray
        }
    }

    private func zoneLabel(_ zone: RuleZone) -> String {
        switch zone {
        case .normal: return "В норме"
        case .warning: return "Внимание"
        case .violation: return "Нарушено"
        case .noData: return "Нет данных"
        }
    }

    private func summaryCircle(normal: Int, total: Int) -> some View {
        let ratio = total > 0 ? Double(normal) / Double(total) : 0
        let color: Color = ratio >= 0.8 ? .green : (ratio >= 0.5 ? .yellow : .red)

        return ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 4)
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 36, height: 36)
    }
}
