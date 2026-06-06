import XCTest
import SwiftData
@testable import LifeAdvisorApp

final class RuleEngineTests: XCTestCase {

    // MARK: - Range primitive tests (binary model)

    func testRangeBothBoundsNormal() {
        let result = evaluateRange(value: 0.20, lower: 0.10, upper: 0.30)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeBothBoundsNearUpperStillNormal() {
        let result = evaluateRange(value: 0.28, lower: 0.10, upper: 0.30)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeBothBoundsNearLowerStillNormal() {
        let result = evaluateRange(value: 0.11, lower: 0.10, upper: 0.30)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeBothBoundsViolationBelow() {
        let result = evaluateRange(value: 0.05, lower: 0.10, upper: 0.30)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.reasonCode, "below_lower")
    }

    func testRangeBothBoundsViolationAbove() {
        let result = evaluateRange(value: 0.35, lower: 0.10, upper: 0.30)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.reasonCode, "exceeds_upper")
    }

    func testRangeUpperOnlyNormal() {
        let result = evaluateRange(value: 0.05, lower: nil, upper: 0.10)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeUpperOnlyNearLimitStillNormal() {
        let result = evaluateRange(value: 0.09, lower: nil, upper: 0.10)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeUpperOnlyViolation() {
        let result = evaluateRange(value: 0.12, lower: nil, upper: 0.10)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.magnitude, 0.02, accuracy: 0.001)
    }

    func testRangeLowerOnlyNormal() {
        let result = evaluateRange(value: 30, lower: 25, upper: nil)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeLowerOnlyNearLimitStillNormal() {
        let result = evaluateRange(value: 28, lower: 25, upper: nil)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeLowerOnlyViolation() {
        let result = evaluateRange(value: 20, lower: 25, upper: nil)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.magnitude, 5.0)
    }

    func testRangeNoBounds() {
        let result = evaluateRange(value: 100, lower: nil, upper: nil)
        XCTAssertEqual(result.zone, .normal)
    }

    // MARK: - Presence tests (9.2)

    func testPresenceFound() {
        let items = [makeItem(category: "whole_grain")]
        let result = evaluatePresence(dailyItems: items, targetCategories: ["whole_grain"], inverse: false)
        XCTAssertEqual(result.zone, .normal)
    }

    func testPresenceMissing() {
        let items = [makeItem(category: "other")]
        let result = evaluatePresence(dailyItems: items, targetCategories: ["whole_grain"], inverse: false)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.reasonCode, "category_missing")
    }

    func testPresenceInverseViolation() {
        let items = [makeItem(category: "processed_meat")]
        let result = evaluatePresence(dailyItems: items, targetCategories: ["processed_meat"], inverse: true)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.reasonCode, "unwanted_category_present")
    }

    func testPresenceInverseNormal() {
        let items = [makeItem(category: "vegetable")]
        let result = evaluatePresence(dailyItems: items, targetCategories: ["processed_meat"], inverse: true)
        XCTAssertEqual(result.zone, .normal)
    }

    func testPresenceNilCategory() {
        let items = [makeItem(category: nil)]
        let result = evaluatePresence(dailyItems: items, targetCategories: ["whole_grain"], inverse: false)
        XCTAssertEqual(result.zone, .violation)
    }

    // MARK: - CountSkipped tests (binary model)

    func testCountSkippedNormal() {
        let result = evaluateCountSkipped(skippedCount: 0, violationThreshold: 4)
        XCTAssertEqual(result.zone, .normal)
    }

    func testCountSkippedBelowThreshold() {
        let result = evaluateCountSkipped(skippedCount: 2, violationThreshold: 4)
        XCTAssertEqual(result.zone, .normal)
    }

    func testCountSkippedViolation() {
        let result = evaluateCountSkipped(skippedCount: 5, violationThreshold: 4)
        XCTAssertEqual(result.zone, .violation)
    }

    // MARK: - Zone comparison tests (binary model)

    func testZoneOrdering() {
        XCTAssertTrue(RuleZone.normal < RuleZone.violation)
        XCTAssertTrue(RuleZone.noData < RuleZone.violation)
    }

    func testZoneWorst() {
        XCTAssertEqual(RuleZone.worst(.normal, .violation), .violation)
        XCTAssertEqual(RuleZone.worst(.normal, .noData), .noData)
        XCTAssertEqual(RuleZone.worst(.normal, .normal), .normal)
    }

    // MARK: - Percentage computation tests (9.4)

    func testFatPercent() {
        // 50g fat * 9 = 450 kcal from fat, total 1000 kcal, should be 45%
        let value = fatPercent(fatGrams: 50, calories: 1000)
        XCTAssertEqual(value, 0.45, accuracy: 0.001)
    }

    func testProteinPercent() {
        let value = proteinPercent(proteinGrams: 25, calories: 1000)
        // 25 * 4 = 100, 100/1000 = 0.10
        XCTAssertEqual(value, 0.10, accuracy: 0.001)
    }

    func testSugarPercent() {
        let value = sugarPercent(sugarGrams: 10, calories: 1000)
        XCTAssertEqual(value, 0.04, accuracy: 0.001)
    }

    func testZeroCaloriesReturnsZero() {
        XCTAssertEqual(fatPercent(fatGrams: 10, calories: 0), 0)
        XCTAssertEqual(proteinPercent(proteinGrams: 10, calories: 0), 0)
    }

    // MARK: - JSON validation tests (9.5)

    func testValidRangeRule() {
        let json = """
        {"id":"test","type":"range","field":"fatPercent","params":{"lower":0.15,"upper":0.30},"warningRatio":0.85,"category":"test","title":"Test","description":"Desc","window":"day"}
        """
        let rule = try? JSONDecoder().decode(RuleDefinition.self, from: Data(json.utf8))
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.id, "test")
        XCTAssertEqual(rule?.params.lower, 0.15)
        XCTAssertEqual(rule?.params.upper, 0.30)
    }

    func testValidPresenceRule() {
        let json = """
        {"id":"test","type":"presence","field":null,"params":{"category":"whole_grain"},"warningRatio":0.85,"category":"test","title":"Test","description":"Desc","window":"day"}
        """
        let rule = try? JSONDecoder().decode(RuleDefinition.self, from: Data(json.utf8))
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.params.category, "whole_grain")
    }

    func testInvalidTypeRule() {
        let json = """
        {"id":"test","type":"unknown","field":"x","params":{},"warningRatio":0.85,"category":"test","title":"Test","description":"Desc","window":"day"}
        """
        let rule = try? JSONDecoder().decode(RuleDefinition.self, from: Data(json.utf8))
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.type, "unknown")
    }

    func testMissingOptionalFields() {
        let json = """
        {"id":"test","type":"range","field":"fatPercent","params":{},"warningRatio":0.85,"category":"test","title":"Test","description":"Desc","window":"day"}
        """
        let rule = try? JSONDecoder().decode(RuleDefinition.self, from: Data(json.utf8))
        XCTAssertNotNil(rule)
        XCTAssertNil(rule?.params.lower)
        XCTAssertNil(rule?.params.upper)
    }

    // MARK: - Incremental calculation tests (9.6)

    // Note: fullRebuild integration test requires nutrition_rules.json in bundle.

    @MainActor
    func testWeekResetRemovesOldViolations() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = RuleEngine()
        engine.configure(context: context)

        // Create an old violation
        let oldDate = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let oldViolation = RuleViolation(
            ruleId: "who_total_fat",
            date: oldDate,
            zone: "violation",
            magnitude: 5.0,
            reasonCode: "exceeds_upper"
        )
        context.insert(oldViolation)
        try context.save()

        engine.resetWeekIfNeeded()

        let descriptor = FetchDescriptor<RuleViolation>()
        let remaining = (try? context.fetch(descriptor)) ?? []
        XCTAssertTrue(remaining.isEmpty, "Old violations should be removed")
    }

    // MARK: - Snapshot generation tests (7.2)

    @MainActor
    func testGenerateViolationsCreatesRangeSnapshotAndContributionItems() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let event = MealEvent(windowLabel: "breakfast", status: .structured)
        event.timestamp = Date()
        let item = EstimateItem(
            name: "Fiber bowl",
            estimatedCalories: 250,
            estimatedProteins: 8,
            estimatedFats: 4,
            estimatedCarbs: 35,
            impactScore: 0.4,
            reason: "",
            sourceMode: .ingredientBreakdown,
            grams: 180
        )
        item.estimatedFiber = 12
        item.mealEvent = event
        context.insert(event)
        context.insert(item)

        let engine = RuleEngine()
        engine.configure(context: context)
        engine.setRulesForTesting([
            RuleDefinition(
                id: "test_fiber",
                type: "range",
                field: "fiberGrams",
                params: RuleParams(lower: 25),
                warningRatio: 0.85,
                category: "macronutrient_balance",
                title: "Fiber",
                description: "At least 25 g",
                window: "day"
            )
        ])

        engine.generateViolations(for: event.timestamp)

        let snapshots = engine.snapshotsForDay(event.timestamp)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.ruleId, "test_fiber")
        XCTAssertEqual(snapshots.first?.zone, RuleZone.violation.rawValue)
        XCTAssertEqual(snapshots.first?.items.count, 1)
        XCTAssertEqual(snapshots.first?.items.first?.absoluteContribution ?? 0, 12, accuracy: 0.001)
    }

    @MainActor
    func testGenerateViolationsCreatesPresenceSnapshotAndContributionItems() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let event = MealEvent(windowLabel: "lunch", status: .structured)
        event.timestamp = Date()
        let item = EstimateItem(
            name: "Salad",
            estimatedCalories: 120,
            estimatedProteins: 3,
            estimatedFats: 2,
            estimatedCarbs: 18,
            impactScore: 0.3,
            reason: "",
            sourceMode: .ingredientBreakdown,
            grams: 150,
            foodCategory: "vegetable"
        )
        item.mealEvent = event
        context.insert(event)
        context.insert(item)

        let engine = RuleEngine()
        engine.configure(context: context)
        engine.setRulesForTesting([
            RuleDefinition(
                id: "test_veg",
                type: "presence",
                field: nil,
                params: RuleParams(category: "vegetable"),
                warningRatio: 0.85,
                category: "food_quality",
                title: "Vegetables",
                description: "Vegetables present",
                window: "day"
            )
        ])

        engine.generateViolations(for: event.timestamp)

        let snapshots = engine.snapshotsForDay(event.timestamp)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.ruleId, "test_veg")
        XCTAssertEqual(snapshots.first?.zone, RuleZone.normal.rawValue)
        XCTAssertEqual(snapshots.first?.items.count, 1)
        XCTAssertEqual(snapshots.first?.items.first?.absoluteContribution ?? 0, 150, accuracy: 0.001)
        XCTAssertEqual(snapshots.first?.items.first?.percentContribution ?? 0, 100, accuracy: 0.001)
    }

    // MARK: - Contribution item tests (7.2, 7.3)

    @MainActor
    func testSignificantViolationsForItem() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let event = MealEvent(windowLabel: "breakfast", status: .structured)
        event.calories = 500
        event.fats = 40
        let item = EstimateItem(
            name: "Fatty food",
            estimatedCalories: 500,
            estimatedProteins: 10,
            estimatedFats: 40,
            estimatedCarbs: 20,
            impactScore: 0.5,
            reason: "",
            sourceMode: .ingredientBreakdown,
            grams: 200
        )
        item.mealEvent = event
        context.insert(item)

        // Create a contribution item for this product with >20% contribution
        let contribItem = RuleContributionItem(
            ruleId: "who_total_fat",
            productName: "Fatty food",
            absoluteContribution: 40,
            percentContribution: 80,
            dayOrderIndex: 0,
            mealEvent: event,
            estimateItem: item
        )
        context.insert(contribItem)

        // Create a violation for the same rule
        let violation = RuleViolation(
            ruleId: "who_total_fat",
            date: Date(),
            zone: "violation",
            magnitude: 0.15,
            reasonCode: "exceeds_upper"
        )
        context.insert(violation)
        try context.save()

        let engine = RuleEngine()
        engine.configure(context: context)

        let sigViolations = engine.significantViolationsForItem(item, date: Date())
        XCTAssertEqual(sigViolations.count, 1)
        XCTAssertEqual(sigViolations.first?.ruleId, "who_total_fat")
        XCTAssertEqual(sigViolations.first?.percentContribution, 80)
    }

    @MainActor
    func testContributionItemBelowThresholdNotHighlighted() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let event = MealEvent(windowLabel: "breakfast", status: .structured)
        event.calories = 500
        let item = EstimateItem(
            name: "Small contributor",
            estimatedCalories: 100,
            estimatedProteins: 2,
            estimatedFats: 2,
            estimatedCarbs: 10,
            impactScore: 0.1,
            reason: "",
            sourceMode: .ingredientBreakdown,
            grams: 50
        )
        item.mealEvent = event
        context.insert(item)

        let contribItem = RuleContributionItem(
            ruleId: "who_total_fat",
            productName: "Small contributor",
            absoluteContribution: 2,
            percentContribution: 15,
            dayOrderIndex: 0,
            mealEvent: event,
            estimateItem: item
        )
        context.insert(contribItem)

        let violation = RuleViolation(
            ruleId: "who_total_fat",
            date: Date(),
            zone: "violation",
            magnitude: 0.05,
            reasonCode: "exceeds_upper"
        )
        context.insert(violation)
        try context.save()

        let engine = RuleEngine()
        engine.configure(context: context)

        let sigViolations = engine.significantViolationsForItem(item, date: Date())
        XCTAssertTrue(sigViolations.isEmpty, "Contributions <=20% should not be highlighted")
    }

    @MainActor
    func testMultipleRulesSortedByContribution() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let event = MealEvent(windowLabel: "breakfast", status: .structured)
        let item = EstimateItem(
            name: "Multi-violating food",
            estimatedCalories: 500,
            estimatedProteins: 5,
            estimatedFats: 35,
            estimatedCarbs: 30,
            impactScore: 0.5,
            reason: "",
            sourceMode: .ingredientBreakdown,
            grams: 300,
            foodCategory: "red_meat"
        )
        item.mealEvent = event
        context.insert(item)

        for (ruleId, percent) in [("who_total_fat", 70.0), ("who_saturated_fat", 50.0)] {
            let contribItem = RuleContributionItem(
                ruleId: ruleId,
                productName: "Multi-violating food",
                absoluteContribution: 35,
                percentContribution: percent,
                dayOrderIndex: 0,
                mealEvent: event,
                estimateItem: item
            )
            context.insert(contribItem)
            let violation = RuleViolation(
                ruleId: ruleId,
                date: Date(),
                zone: "violation",
                magnitude: 0.1,
                reasonCode: "exceeds_upper"
            )
            context.insert(violation)
        }
        try context.save()

        let engine = RuleEngine()
        engine.configure(context: context)

        let sigViolations = engine.significantViolationsForItem(item, date: Date())
        XCTAssertEqual(sigViolations.count, 2)
        // Should be sorted by percent contribution descending
        XCTAssertEqual(sigViolations[0].ruleId, "who_total_fat")
        XCTAssertEqual(sigViolations[1].ruleId, "who_saturated_fat")
    }

    @MainActor
    func testDeficitRuleContributionDoesNotHighlightProduct() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let event = MealEvent(windowLabel: "breakfast", status: .structured)
        let item = EstimateItem(
            name: "Banana",
            estimatedCalories: 90,
            estimatedProteins: 1,
            estimatedFats: 0,
            estimatedCarbs: 20,
            impactScore: 0.3,
            reason: "",
            sourceMode: .ingredientBreakdown,
            grams: 120,
            foodCategory: "fruit"
        )
        item.mealEvent = event
        context.insert(item)

        let contribItem = RuleContributionItem(
            ruleId: "who_fruits_vegetables",
            productName: "Banana",
            absoluteContribution: 120,
            percentContribution: 100,
            dayOrderIndex: 0,
            mealEvent: event,
            estimateItem: item
        )
        context.insert(contribItem)

        let violation = RuleViolation(
            ruleId: "who_fruits_vegetables",
            date: Date(),
            zone: "violation",
            magnitude: 280,
            reasonCode: "below_lower"
        )
        context.insert(violation)
        try context.save()

        let engine = RuleEngine()
        engine.configure(context: context)

        let sigViolations = engine.significantViolationsForItem(item, date: Date())
        XCTAssertTrue(sigViolations.isEmpty, "Helpful contribution for deficit rules must not trigger product highlighting")
    }

    @MainActor
    func testUnwantedCategoryRuleStillHighlightsProduct() async throws {
        let container = try makeContainer()
        let context = container.mainContext

        let event = MealEvent(windowLabel: "dinner", status: .structured)
        let item = EstimateItem(
            name: "Processed sausage",
            estimatedCalories: 300,
            estimatedProteins: 14,
            estimatedFats: 24,
            estimatedCarbs: 4,
            impactScore: 0.8,
            reason: "",
            sourceMode: .ingredientBreakdown,
            grams: 140,
            foodCategory: "processed_meat"
        )
        item.mealEvent = event
        context.insert(item)

        let contribItem = RuleContributionItem(
            ruleId: "who_processed_meat",
            productName: "Processed sausage",
            absoluteContribution: 140,
            percentContribution: 100,
            dayOrderIndex: 0,
            mealEvent: event,
            estimateItem: item
        )
        context.insert(contribItem)

        let violation = RuleViolation(
            ruleId: "who_processed_meat",
            date: Date(),
            zone: "violation",
            magnitude: 1,
            reasonCode: "unwanted_category_present"
        )
        context.insert(violation)
        try context.save()

        let engine = RuleEngine()
        engine.configure(context: context)

        let sigViolations = engine.significantViolationsForItem(item, date: Date())
        XCTAssertEqual(sigViolations.count, 1)
        XCTAssertEqual(sigViolations.first?.ruleId, "who_processed_meat")
    }

    // MARK: - Presentation formatting tests (7.4)

    func testContributionPresentationForGramRuleShowsAbsoluteAndPercent() {
        let text = RuleContributionPresentation.contributionText(
            absoluteContribution: 11,
            percentContribution: 37,
            field: "fiberGrams",
            language: .en
        )
        XCTAssertEqual(text, "11 g (37%)")
    }

    func testContributionPresentationForPercentRuleShowsOnlyMetricValue() {
        let text = RuleContributionPresentation.contributionText(
            absoluteContribution: 0.062,
            percentContribution: 41,
            field: "fatPercent",
            language: .en
        )
        XCTAssertEqual(text, "6.2%")
    }

    func testHumanReadableNormForLowerBoundRule() {
        let rule = RuleDefinition(
            id: "test_fiber",
            type: "range",
            field: "fiberGrams",
            params: RuleParams(lower: 25),
            warningRatio: 0.85,
            category: "macronutrient_balance",
            title: nil,
            description: nil,
            window: "day"
        )

        XCTAssertEqual(
            RuleContributionPresentation.normText(for: rule, language: .ru),
            "Норма: не менее 25 г"
        )
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MealEvent.self,
            EstimateItem.self,
            MealWindow.self,
            NutritionRuleConfig.self,
            RuleViolation.self,
            RuleContributionSnapshot.self,
            RuleContributionItem.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeItem(category: String?) -> EstimateItem {
        EstimateItem(
            name: "test",
            estimatedCalories: 100,
            estimatedProteins: 5,
            estimatedFats: 5,
            estimatedCarbs: 10,
            impactScore: 0.5,
            reason: "",
            sourceMode: .ingredientBreakdown,
            grams: 100,
            foodCategory: category
        )
    }

    private func fatPercent(fatGrams: Double, calories: Double) -> Double {
        guard calories > 0 else { return 0 }
        return (fatGrams * 9) / calories
    }

    private func proteinPercent(proteinGrams: Double, calories: Double) -> Double {
        guard calories > 0 else { return 0 }
        return (proteinGrams * 4) / calories
    }

    private func sugarPercent(sugarGrams: Double, calories: Double) -> Double {
        guard calories > 0 else { return 0 }
        return (sugarGrams * 4) / calories
    }
}
