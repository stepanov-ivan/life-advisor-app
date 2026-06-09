import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var selectedDate = DashboardDateLogic.startOfDay(Date())
    @StateObject private var agentSession = AgentSessionStore()

    var body: some View {
        ZStack(alignment: .bottom) {
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

            if !agentSession.hasActiveSession {
                Button {
                    selectedTab = 0
                    agentSession.presentChat(for: .meal)
                } label: {
                    Image(systemName: "sparkles")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 18)
            }
        }
        .environmentObject(agentSession)
    }
}
