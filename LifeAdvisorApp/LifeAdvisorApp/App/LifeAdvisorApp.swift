import SwiftUI
import SwiftData

@main
struct LifeAdvisorApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                MealEvent.self,
                Ingredient.self,
                FoodItem.self,
                MealWindow.self,
                MealTemplate.self,
                TemplateIngredient.self,
                DailyAdvice.self,
                Recommendation.self
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        seedFoodDatabaseIfNeeded()
        setupDefaultMealWindowsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .modelContainer(modelContainer)
    }

    private func seedFoodDatabaseIfNeeded() {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<FoodItem>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else { return }
        FoodDatabaseSeeder.seed(into: context)
    }

    private func setupDefaultMealWindowsIfNeeded() {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<MealWindow>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else { return }

        let windows: [(String, Int, Int, Int, Int)] = [
            ("Завтрак", 7, 0, 10, 0),
            ("Обед", 12, 0, 15, 0),
            ("Ужин", 18, 0, 21, 0)
        ]
        for (i, (name, sh, sm, eh, em)) in windows.enumerated() {
            let window = MealWindow(
                name: name,
                startHour: sh,
                startMinute: sm,
                endHour: eh,
                endMinute: em,
                order: i
            )
            context.insert(window)
        }
        try? context.save()
    }
}
