import XCTest
import SwiftData
@testable import LifeAdvisorApp

@MainActor
final class EstimationRuntimeTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MealEvent.self,
            EstimateItem.self,
            MemorySuggestion.self,
            MemorySuggestionAlias.self,
            MemoryHypothesis.self,
            MemoryDataGap.self,
            MealWindow.self,
            DailyAdvice.self,
            Recommendation.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func moscowCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        return calendar
    }

    func testLifecycleStatusesCanTransition() throws {
        let event = MealEvent(windowLabel: "Завтрак", status: .pendingEstimation, rawText: "Биг тейсти")
        XCTAssertEqual(event.status, .pendingEstimation)

        event.status = .structured
        XCTAssertEqual(event.status, .structured)

        event.status = .parseFailed
        XCTAssertEqual(event.status, .parseFailed)
        event.structureSource = .memorySuggestion
        XCTAssertEqual(event.structureSource, .memorySuggestion)
        event.structureSource = .manualOverride
        XCTAssertEqual(event.structureSource, .manualOverride)
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
        let memory = MemorySuggestion(
            canonicalKey: "a b",
            displayText: "a b",
            calories: 600,
            proteins: 20,
            fats: 20,
            carbs: 70
        )

        let applied = EstimationRuntime.applySuggestionPrior(totals: totals, suggestion: memory)

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

    func testOutOfSyncDetection() {
        XCTAssertFalse(MemoryEngine.isOutOfSync(selectedText: "Кефир 2.5 300г", currentText: "кефир 2.5% 300г"))
        XCTAssertTrue(MemoryEngine.isOutOfSync(selectedText: "Биг мак", currentText: "Биг тейсти"))
    }

    func testSuggestionLimitAndRanking() {
        let now = Date()
        let events = (0..<60).map { index -> MealEvent in
            let event = MealEvent(windowLabel: "Обед", timestamp: now.addingTimeInterval(TimeInterval(-index * 60)), status: .structured, rawText: index % 2 == 0 ? "Кефир 300г" : "Биг мак")
            event.applyTotals(calories: index % 2 == 0 ? 150 : 500, proteins: 10, fats: 10, carbs: 10)
            return event
        }
        let suggestions = MemoryEngine.topSuggestions(query: "кеф", from: events, suggestions: [], limit: 5)
        XCTAssertLessThanOrEqual(suggestions.count, 5)
        XCTAssertTrue(suggestions.first?.text.lowercased().contains("кеф") ?? false)
    }

    func testDataGapAutoCloseAfterTwoConfirmations() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let fingerprint = MemoryEngine.normalize("Кефир 300г")

        MemoryEngine.recordDataGap(title: "Нет порции", fingerprint: fingerprint, context: context)
        MemoryEngine.confirmDataGap(fingerprint: fingerprint, context: context)
        MemoryEngine.confirmDataGap(fingerprint: fingerprint, context: context)
        try context.save()

        let expectedKey = "gap:\(fingerprint)"
        let descriptor = FetchDescriptor<MemoryDataGap>(predicate: #Predicate { $0.key == expectedKey })
        let gap = try context.fetch(descriptor).first
        XCTAssertNotNil(gap)
        XCTAssertEqual(gap?.confirmationCount, 2)
        XCTAssertTrue(gap?.resolved ?? false)
    }

    func testHypothesisSignalThreshold() throws {
        let container = try makeContainer()
        let context = container.mainContext
        MemoryEngine.applyHypothesisSignal(key: "no_fish", title: "Возможно не ест рыбу", context: context)
        MemoryEngine.applyHypothesisSignal(key: "no_fish", title: "Возможно не ест рыбу", context: context)
        try context.save()

        let descriptor = FetchDescriptor<MemoryHypothesis>(predicate: #Predicate { $0.key == "no_fish" })
        let hypothesis = try context.fetch(descriptor).first
        XCTAssertEqual(hypothesis?.signalCount, 2)
        XCTAssertNotNil(hypothesis?.nextPromptAt)
    }

    func testHypothesisSnoozeAndConflictLifecycle() throws {
        let container = try makeContainer()
        let context = container.mainContext
        MemoryEngine.applyHypothesisSignal(key: "avoid_fish", title: "avoid fish?", context: context)
        MemoryEngine.applyHypothesisSignal(key: "avoid_fish", title: "avoid fish?", context: context)
        let descriptor = FetchDescriptor<MemoryHypothesis>(predicate: #Predicate { $0.key == "avoid_fish" })
        guard let hypothesis = try context.fetch(descriptor).first else {
            return XCTFail("Hypothesis not created")
        }

        XCTAssertEqual(hypothesis.status, .pendingConfirmation)
        XCTAssertNotNil(hypothesis.nextPromptAt)

        MemoryEngine.snoozeHypothesis(hypothesis)
        let snoozeDate = hypothesis.nextPromptAt
        XCTAssertNotNil(snoozeDate)
        XCTAssertTrue((snoozeDate?.timeIntervalSinceNow ?? 0) > 2 * 24 * 60 * 60)

        MemoryEngine.confirmHypothesis(hypothesis)
        XCTAssertEqual(hypothesis.status, .confirmed)

        MemoryEngine.registerHypothesisConflict(hypothesis)
        XCTAssertEqual(hypothesis.status, .underReview)
        XCTAssertNotNil(hypothesis.cooldownUntil)
        XCTAssertNotNil(hypothesis.lastConflictAt)
    }

    func testCandidatePromotionAndVersionLimit() throws {
        let container = try makeContainer()
        let context = container.mainContext

        MemoryEngine.upsertPrimarySuggestion(
            text: "Кефир 300г",
            totals: (calories: 150, proteins: 9, fats: 7, carbs: 12),
            context: context
        )
        MemoryEngine.upsertPrimarySuggestion(
            text: "Кефир 300г",
            totals: (calories: 280, proteins: 12, fats: 10, carbs: 20),
            context: context
        )
        MemoryEngine.upsertPrimarySuggestion(
            text: "Кефир 300г",
            totals: (calories: 280, proteins: 12, fats: 10, carbs: 20),
            context: context
        )
        MemoryEngine.upsertPrimarySuggestion(
            text: "Кефир 300г",
            totals: (calories: 320, proteins: 15, fats: 12, carbs: 24),
            context: context
        )
        MemoryEngine.upsertPrimarySuggestion(
            text: "Кефир 300г",
            totals: (calories: 320, proteins: 15, fats: 12, carbs: 24),
            context: context
        )
        try context.save()

        let key = MemoryEngine.normalize("Кефир 300г")
        let descriptor = FetchDescriptor<MemorySuggestion>(
            predicate: #Predicate { $0.canonicalKey == key },
            sortBy: [SortDescriptor(\MemorySuggestion.lastUsedAt, order: .reverse)]
        )
        let versions = try context.fetch(descriptor)
        XCTAssertLessThanOrEqual(versions.count, 3)
        XCTAssertTrue(versions.contains(where: { !$0.isCandidate }))
    }

    func testOutOfSyncPromptDecisionContract() {
        XCTAssertTrue(
            MemoryPresentation.shouldPromptOutOfSync(
                source: .memorySuggestion,
                selectedText: "кефир 300г",
                currentText: "кефир 500г"
            )
        )
        XCTAssertFalse(
            MemoryPresentation.shouldPromptOutOfSync(
                source: .llm,
                selectedText: "кефир 300г",
                currentText: "кефир 500г"
            )
        )
    }

    func testExplainabilityTopFactorsContract() {
        let item = EstimateItem(
            name: "Орехи",
            estimatedCalories: 200,
            estimatedProteins: 5,
            estimatedFats: 18,
            estimatedCarbs: 4,
            impactScore: 0.9,
            reason: "Высокая плотность калорий",
            highCalorieFlag: true,
            sourceMode: .ingredientBreakdown
        )
        let factors = MemoryPresentation.explainabilityFactors(
            source: .memorySuggestion,
            confidence: "medium",
            memoryApplied: true,
            sourceMode: .ingredientBreakdown,
            items: [item]
        )
        XCTAssertGreaterThanOrEqual(factors.count, 4)

        let top2 = MemoryPresentation.topExplainabilityFactors(factors, showAll: false)
        XCTAssertEqual(top2.count, 2)
        let all = MemoryPresentation.topExplainabilityFactors(factors, showAll: true)
        XCTAssertEqual(all.count, factors.count)
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
                grams: 180,
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
                grams: 90,
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

    func testDashboardDateLogicRoundTripAndFutureGuard() {
        let calendar = moscowCalendar()
        let now = Date(timeIntervalSince1970: 1_747_000_000)
        let todayKey = DashboardDateLogic.dayKey(for: now, calendar: calendar)
        let restored = DashboardDateLogic.date(from: todayKey, calendar: calendar)
        XCTAssertNotNil(restored)
        XCTAssertEqual(DashboardDateLogic.dayKey(for: restored!, calendar: calendar), todayKey)

        let future = calendar.date(byAdding: .day, value: 2, to: now)!
        XCTAssertTrue(DashboardDateLogic.isFutureDate(future, now: now, calendar: calendar))
        XCTAssertFalse(DashboardDateLogic.isFutureDate(now, now: now, calendar: calendar))
    }

    func testSelectedDayFilterRangeIncludesOnlyChosenDay() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let calendar = moscowCalendar()
        let selected = DashboardDateLogic.startOfDay(Date(timeIntervalSince1970: 1_747_000_000), calendar: calendar)
        let range = DashboardDateLogic.dayRange(for: selected, calendar: calendar)

        let inDay = MealEvent(
            windowLabel: "Завтрак",
            timestamp: calendar.date(byAdding: .hour, value: 9, to: range.start)!,
            status: .structured,
            rawText: "Овсянка 250г"
        )
        let prevDay = MealEvent(
            windowLabel: "Обед",
            timestamp: calendar.date(byAdding: .hour, value: -2, to: range.start)!,
            status: .structured,
            rawText: "Паста"
        )
        context.insert(inDay)
        context.insert(prevDay)
        try context.save()

        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<MealEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\MealEvent.timestamp, order: .reverse)]
        )
        let events = try context.fetch(descriptor)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.windowLabel, "Завтрак")
    }

    func testAdviceUsefulnessFiltersTechnicalAndShortText() {
        XCTAssertFalse(MemoryPresentation.isAdviceUseful(nil))
        XCTAssertFalse(MemoryPresentation.isAdviceUseful("коротко"))
        XCTAssertFalse(MemoryPresentation.isAdviceUseful("Источник структуры: memorySuggestion, уверенность модели: medium"))
        XCTAssertTrue(MemoryPresentation.isAdviceUseful("Добавьте 20-30 г белка в следующий прием пищи, чтобы закрыть дефицит по дню."))
        XCTAssertNil(MemoryPresentation.cleanAdviceText("режим оценки: ingredient_breakdown"))
    }

    func testEstimateItemGramsAndLockContract() {
        let item = EstimateItem(
            name: "Кефир",
            estimatedCalories: 60,
            estimatedProteins: 3,
            estimatedFats: 2,
            estimatedCarbs: 4,
            impactScore: 0.4,
            reason: "Базовая оценка",
            highCalorieFlag: false,
            sourceMode: .ingredientBreakdown,
            grams: 300.5
        )

        XCTAssertEqual(item.grams, 300.5, accuracy: 0.001)
        XCTAssertEqual(item.baseGrams, 300.5, accuracy: 0.001)
        XCTAssertEqual(item.baseCalories, 60, accuracy: 0.001)
        XCTAssertFalse(item.macrosLocked)

        item.macrosLocked = true
        item.estimatedCalories = 120
        XCTAssertTrue(item.macrosLocked)
        XCTAssertEqual(item.estimatedCalories, 120, accuracy: 0.001)
        XCTAssertEqual(item.baseCalories, 60, accuracy: 0.001)
    }
}
