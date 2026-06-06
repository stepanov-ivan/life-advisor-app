import SwiftUI
import SwiftData

struct RuleDetailView: View {
    let rule: RuleDefinition
    @StateObject private var languageManager = AppLanguageManager.shared
    @Binding var selectedDate: Date
    @Binding var selectedTab: Int

    var body: some View {
        let localizer = RulePresentationLocalizer(language: languageManager.effectiveLanguage)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(localizer.ruleTitle(for: rule.id))
                    .font(.headline)

                Text(localizer.ruleDescription(for: rule.id))
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(languageManager.effectiveLanguage == .ru
                     ? "Подробная аналитика правила перенесена в дневную панель правил на дашборде."
                     : "Detailed rule analytics moved to the daily rules panel on the dashboard.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button(languageManager.effectiveLanguage == .ru ? "Открыть дашборд" : "Open dashboard") {
                    selectedDate = Calendar.current.startOfDay(for: selectedDate)
                    selectedTab = 0
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(localizer.ruleTitle(for: rule.id))
    }
}
