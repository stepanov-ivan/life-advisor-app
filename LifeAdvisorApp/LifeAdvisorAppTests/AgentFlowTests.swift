import XCTest
import SwiftData
@testable import LifeAdvisorApp

@MainActor
final class AgentFlowTests: XCTestCase {
    private func makeWindows() -> [MealWindow] {
        [
            MealWindow(windowId: "breakfast", name: "Завтрак", startHour: 7, startMinute: 0, endHour: 10, endMinute: 0, order: 0),
            MealWindow(windowId: "lunch", name: "Обед", startHour: 12, startMinute: 0, endHour: 15, endMinute: 0, order: 1),
            MealWindow(windowId: "dinner", name: "Ужин", startHour: 18, startMinute: 0, endHour: 21, endMinute: 0, order: 2)
        ]
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MealEvent.self,
            EstimateItem.self,
            MealWindow.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testMealScenarioClassifierDetectsCreate() async {
        let context = MealPlanningContext(selectedDate: Date(), dayEvents: [], windows: makeWindows())
        let result = await MealScenarioClassifier.classify("сегодня ел овсянку и кефир", context: context)
        XCTAssertEqual(result.scenario, .create)
    }

    func testMealScenarioClassifierDetectsEdit() async {
        let context = MealPlanningContext(selectedDate: Date(), dayEvents: [], windows: makeWindows())
        let result = await MealScenarioClassifier.classify("убери мороженое из сегодняшнего ужина", context: context)
        XCTAssertEqual(result.scenario, .edit)
    }

    func testMealStepPlannerBuildsSeveralStepsForCommaSeparatedInput() async throws {
        let context = MealPlanningContext(selectedDate: Date(), dayEvents: [], windows: makeWindows())
        let classification = MealScenarioClassification(scenario: .create, resolvedDay: Date())
        let plan = try await MealStepPlanner.plan(
            message: "овсянка, кефир, смэшбургер, окрошка, мороженое",
            classification: classification,
            context: context
        )

        XCTAssertEqual(plan.steps.count, 3)
        XCTAssertEqual(plan.steps[0].type, .create)
        XCTAssertFalse(plan.steps[0].products.isEmpty)
    }

    func testMealStepPlannerKeepsPureEditChain() async throws {
        let context = MealPlanningContext(selectedDate: Date(), dayEvents: [], windows: makeWindows())
        let classification = MealScenarioClassification(scenario: .edit, resolvedDay: Date())
        let plan = try await MealStepPlanner.plan(
            message: "убери мороженое из ужина",
            classification: classification,
            context: context
        )

        XCTAssertTrue(plan.steps.allSatisfy { $0.type == .edit })
    }

    func testMealStepPlannerBuildsMultiDayChain() async throws {
        let baseDay = Date()
        let context = MealPlanningContext(selectedDate: baseDay, dayEvents: [], windows: makeWindows())
        let classification = MealScenarioClassification(scenario: .create, resolvedDay: baseDay)
        let plan = try await MealStepPlanner.plan(
            message: "сегодня овсянка, кефир, завтра суп, рис",
            classification: classification,
            context: context
        )

        let days = Set(plan.steps.map { DashboardDateLogic.dayKey(for: $0.day) })
        XCTAssertEqual(days.count, 2)
    }

    func testMealStepPlannerDoesNotForceThreeSlotsForThreeProductsWithoutExplicitSlots() async throws {
        let context = MealPlanningContext(selectedDate: Date(), dayEvents: [], windows: makeWindows())
        let classification = MealScenarioClassification(scenario: .create, resolvedDay: Date())
        let plan = try await MealStepPlanner.plan(
            message: "овсянка, кефир, банан",
            classification: classification,
            context: context
        )

        XCTAssertEqual(plan.steps.count, 2)
    }

    func testAgentSessionAllowsSingleExecutionSession() {
        let store = AgentSessionStore()
        store.presentChat(for: .meal)
        XCTAssertEqual(store.phase, .chatInput)
        XCTAssertTrue(store.hasActiveSession)

        let session = MealExecutionSession(
            scenario: .create,
            originalMessage: "овсянка",
            steps: [
                MealExecutionStep(
                    type: .create,
                    day: Date(),
                    windowId: "breakfast",
                    title: "Завтрак",
                    products: [
                        MealProductDraft(
                            name: "Овсянка",
                            grams: 100,
                            estimatedCalories: 120,
                            estimatedProteins: 5,
                            estimatedFats: 4,
                            estimatedCarbs: 15
                        )
                    ],
                    sourceText: "овсянка"
                )
            ]
        )
        store.startMealExecution(session)
        store.presentChat(for: .meal)

        XCTAssertEqual(store.phase, .executing)
        XCTAssertNotNil(store.mealSession)
    }

    func testPlanningStateKeepsChatPresented() {
        let store = AgentSessionStore()
        store.presentChat(for: .meal)
        store.beginPlanning()

        XCTAssertEqual(store.phase, .planning)
        XCTAssertTrue(store.isChatPresented)
        XCTAssertEqual(store.activeDomain, .meal)
    }

    func testChatDismissDoesNotResetExecutingSession() {
        let store = AgentSessionStore()
        store.startMealExecution(
            MealExecutionSession(
                scenario: .create,
                originalMessage: "овсянка",
                steps: [
                    MealExecutionStep(
                        type: .create,
                        day: Date(),
                        windowId: "breakfast",
                        title: "Завтрак",
                        products: [
                            MealProductDraft(
                                name: "Овсянка",
                                grams: 100,
                                estimatedCalories: 120,
                                estimatedProteins: 5,
                                estimatedFats: 4,
                                estimatedCarbs: 15
                            )
                        ],
                        sourceText: "овсянка"
                    )
                ]
            )
        )

        store.handleChatPresentationChange(isPresented: false)

        XCTAssertEqual(store.phase, .executing)
        XCTAssertNotNil(store.mealSession)
        XCTAssertEqual(store.activeDomain, .meal)
    }

    func testMealProductDraftUpdatesMacrosWhenGramsChange() {
        var product = MealProductDraft(
            name: "Овсянка",
            grams: 100,
            estimatedCalories: 120,
            estimatedProteins: 5,
            estimatedFats: 4,
            estimatedCarbs: 15
        )

        product.updateGrams(200)

        XCTAssertEqual(product.grams, 200, accuracy: 0.001)
        XCTAssertEqual(product.estimatedCalories, 240, accuracy: 0.001)
        XCTAssertEqual(product.estimatedProteins, 10, accuracy: 0.001)
    }

    func testCreateConflictResolveDetectedWhenDateAndMealSlotOccupied() {
        let day = DashboardDateLogic.startOfDay(Date())
        let existing = MealEvent(windowLabel: "breakfast", timestamp: day, status: .structured, rawText: "овсянка")
        let step = MealExecutionStep(
            type: .create,
            day: day,
            windowId: "breakfast",
            title: "Завтрак",
            products: [
                MealProductDraft(
                    name: "Кефир",
                    grams: 250,
                    estimatedCalories: 120,
                    estimatedProteins: 6,
                    estimatedFats: 5,
                    estimatedCarbs: 10
                )
            ],
            sourceText: "кефир"
        )

        let resolve = MealResolveEngine.resolveKind(for: step, existingEvent: existing)

        XCTAssertEqual(resolve, .createConflict(existingWindowId: "breakfast"))
    }

    func testCancelKeepsCommittedMealsAndDropsUnconfirmedTail() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let committedEvent = MealEvent(windowLabel: "breakfast", timestamp: Date(), status: .structured, rawText: "овсянка")
        committedEvent.applyTotals(calories: 250, proteins: 10, fats: 6, carbs: 35)
        context.insert(committedEvent)
        try context.save()

        let store = AgentSessionStore()
        store.startMealExecution(
            MealExecutionSession(
                scenario: .create,
                originalMessage: "сегодня овсянка, суп",
                steps: [
                    MealExecutionStep(
                        type: .create,
                        day: Date(),
                        windowId: "breakfast",
                        title: "Завтрак",
                        products: [
                            MealProductDraft(
                                name: "Овсянка",
                                grams: 100,
                                estimatedCalories: 120,
                                estimatedProteins: 5,
                                estimatedFats: 4,
                                estimatedCarbs: 15
                            )
                        ],
                        sourceText: "овсянка",
                        state: .committed
                    ),
                    MealExecutionStep(
                        type: .create,
                        day: Date(),
                        windowId: "lunch",
                        title: "Обед",
                        products: [
                            MealProductDraft(
                                name: "Суп",
                                grams: 300,
                                estimatedCalories: 180,
                                estimatedProteins: 8,
                                estimatedFats: 7,
                                estimatedCarbs: 20
                            )
                        ],
                        sourceText: "суп",
                        state: .draft
                    )
                ],
                activeStepIndex: 1
            )
        )

        store.cancel()

        let events = try context.fetch(FetchDescriptor<MealEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.windowLabel, "breakfast")
        XCTAssertEqual(events.first?.rawText, "овсянка")
        XCTAssertNil(store.mealSession)
        XCTAssertEqual(store.phase, .cancelled)
    }

    func testPlannerDayOffsetIsClampedToSupportedRange() {
        XCTAssertEqual(LLMClient.clampedPlannerDayOffset(nil), 0)
        XCTAssertEqual(LLMClient.clampedPlannerDayOffset(-3), -1)
        XCTAssertEqual(LLMClient.clampedPlannerDayOffset(3), 1)
    }
}
