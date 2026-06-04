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
        let allRules = engine.allRules()
        let grouped = Dictionary(grouping: allRules) { $0.categoryTitle }

        return List {
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
        let enabled = engine.isRuleEnabled(rule.id)

        return HStack(spacing: 12) {
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
            }

            Toggle("", isOn: Binding(
                get: { engine.isRuleEnabled(rule.id) },
                set: { engine.setRuleEnabled(rule.id, enabled: $0) }
            ))
            .labelsHidden()
        }
    }
}
