import SwiftUI
import SwiftData

struct RulesListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var engine = RuleEngine()
    @StateObject private var languageManager = AppLanguageManager.shared

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
        let sections = RuleGroupingPolicy(language: languageManager.effectiveLanguage)
            .sections(for: allRules, surface: .rulesList)
        let ruleMap = Dictionary(uniqueKeysWithValues: allRules.map { ($0.id, $0) })

        return List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.ruleIds, id: \.self) { ruleId in
                        if let rule = ruleMap[ruleId] {
                            ruleRow(rule)
                        }
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: RuleDefinition) -> some View {
        let enabled = engine.isRuleEnabled(rule.id)
        let localizer = RulePresentationLocalizer(language: languageManager.effectiveLanguage)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.ruleTitle(for: rule.id))
                    .font(.body)
                    .foregroundColor(enabled ? .primary : .secondary)
                Text(localizer.ruleDescription(for: rule.id))
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
