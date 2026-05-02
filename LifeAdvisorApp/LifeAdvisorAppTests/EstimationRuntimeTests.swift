import XCTest
import SwiftData
@testable import LifeAdvisorApp

@MainActor
final class EstimationRuntimeTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MealEvent.self,
            EstimateItem.self,
            EstimationMemory.self,
            MealWindow.self,
            DailyAdvice.self,
            Recommendation.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testLifecycleStatusesCanTransition() throws {
        let event = MealEvent(windowLabel: "Завтрак", status: .pendingEstimation, rawText: "Биг тейсти")
        XCTAssertEqual(event.status, .pendingEstimation)

        event.status = .structured
        XCTAssertEqual(event.status, .structured)

        event.status = .parseFailed
        XCTAssertEqual(event.status, .parseFailed)
    }

    func testParseFailedCanPreserveLastGoodTotals() throws {
        let event = MealEvent(windowLabel: "Завтрак", status: .structured, rawText: "Биг тейсти")
        event.applyTotals(calories: 700, proteins: 25, fats: 40, carbs: 50)

        let oldTotals = (event.calories, event.proteins, event.fats, event.carbs)
        event.status = .parseFailed
        event.parseErrorSummary = "timeout"
        event.applyTotals(calories: oldTotals.0, proteins: oldTotals.1, fats: oldTotals.2, carbs: oldTotals.3)

        XCTAssertEqual(event.calories, 700, accuracy: 0.001)
        XCTAssertEqual(event.proteins, 25, accuracy: 0.001)
        XCTAssertEqual(event.status, .parseFailed)
    }

    func testMemoryPriorIsNonBlockingAverage() {
        let totals = LLMClient.Totals(calories: 800, proteins: 30, fats: 30, carbs: 90)
        let memory = EstimationMemory(fingerprint: "a b", calories: 600, proteins: 20, fats: 20, carbs: 70)

        let applied = EstimationRuntime.applyMemoryPrior(totals: totals, memory: memory)

        XCTAssertEqual(applied.calories, 700, accuracy: 0.001)
        XCTAssertEqual(applied.proteins, 25, accuracy: 0.001)
        XCTAssertEqual(applied.fats, 25, accuracy: 0.001)
        XCTAssertEqual(applied.carbs, 80, accuracy: 0.001)
    }

    func testLowConfidenceWarningIsNonBlockingSignal() {
        XCTAssertTrue(EstimationRuntime.lowConfidenceWarningVisible("low"))
        XCTAssertFalse(EstimationRuntime.lowConfidenceWarningVisible("medium"))
        XCTAssertFalse(EstimationRuntime.lowConfidenceWarningVisible(nil))
    }

    func testSnapshotOverwriteReplacesOldItems() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let event = MealEvent(windowLabel: "Обед", status: .structured, rawText: "бургер")
        context.insert(event)

        let old = EstimateItem(
            name: "old",
            estimatedCalories: 100,
            estimatedProteins: 10,
            estimatedFats: 2,
            estimatedCarbs: 12,
            impactScore: 0.4,
            reason: "old",
            highCalorieFlag: false,
            sourceMode: .compositeItem
        )
        old.mealEvent = event
        context.insert(old)
        try context.save()

        let newItems = [
            LLMClient.EstimateItemResult(
                name: "new-1",
                estimatedCalories: 300,
                estimatedProteins: 12,
                estimatedFats: 11,
                estimatedCarbs: 28,
                impactScore: 0.9,
                reason: "new",
                highCalorieFlag: true
            ),
            LLMClient.EstimateItemResult(
                name: "new-2",
                estimatedCalories: 120,
                estimatedProteins: 4,
                estimatedFats: 3,
                estimatedCarbs: 18,
                impactScore: 0.3,
                reason: "new",
                highCalorieFlag: false
            )
        ]

        EstimationRuntime.overwriteSnapshot(event: event, with: newItems, mode: "ingredient_breakdown", modelContext: context)
        try context.save()

        let descriptor = FetchDescriptor<EstimateItem>()
        let items = try context.fetch(descriptor).filter { $0.mealEvent?.persistentModelID == event.persistentModelID }

        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains(where: { $0.name == "new-1" }))
        XCTAssertFalse(items.contains(where: { $0.name == "old" }))
    }

    func testEstimateItemModelPersistsAfterContainerRecreate() throws {
        let first = try makeContainer()
        let firstContext = first.mainContext
        let event = MealEvent(windowLabel: "Ужин", status: .structured, rawText: "кефир")
        firstContext.insert(event)
        let item = EstimateItem(
            name: "кефир",
            estimatedCalories: 150,
            estimatedProteins: 9,
            estimatedFats: 7,
            estimatedCarbs: 12,
            impactScore: 0.2,
            reason: "ok",
            highCalorieFlag: false,
            sourceMode: .compositeItem
        )
        item.mealEvent = event
        firstContext.insert(item)
        try firstContext.save()

        let second = try makeContainer()
        let secondContext = second.mainContext
        let fetched = try secondContext.fetch(FetchDescriptor<EstimateItem>())

        XCTAssertEqual(fetched.count, 0)
    }
}
