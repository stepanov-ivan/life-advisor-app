import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var selectedDate = DashboardDateLogic.startOfDay(Date())

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedDate: $selectedDate)
                .tabItem {
                    Label("Дашборд", systemImage: "square.grid.2x2")
                }
                .tag(0)

            AnalyticsView()
                .tabItem {
                    Label("Аналитика", systemImage: "chart.bar")
                }
                .tag(1)

            RulesListView()
                .tabItem {
                    Label("Правила", systemImage: "checklist")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gear")
                }
                .tag(3)
        }
    }
}
