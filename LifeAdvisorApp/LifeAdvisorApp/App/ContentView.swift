import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Дашборд", systemImage: "square.grid.2x2")
                }
            AnalyticsView()
                .tabItem {
                    Label("Аналитика", systemImage: "chart.bar")
                }
            SettingsView()
                .tabItem {
                    Label("Настройки", systemImage: "gear")
                }
        }
    }
}
