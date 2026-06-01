import XCTest
import SwiftData
@testable import LifeAdvisorApp

final class RuleEngineTests: XCTestCase {

    // MARK: - Range primitive tests (9.1)

    func testRangeBothBoundsNormal() {
        let result = evaluateRange(value: 0.20, lower: 0.10, upper: 0.30, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeBothBoundsWarningApproachingUpper() {
        let result = evaluateRange(value: 0.28, lower: 0.10, upper: 0.30, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .warning)
        XCTAssertEqual(result.reasonCode, "approaching_upper")
    }

    func testRangeBothBoundsWarningApproachingLower() {
        let result = evaluateRange(value: 0.11, lower: 0.10, upper: 0.30, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .warning)
    }

    func testRangeBothBoundsViolationBelow() {
        let result = evaluateRange(value: 0.05, lower: 0.10, upper: 0.30, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.reasonCode, "below_lower")
    }

    func testRangeBothBoundsViolationAbove() {
        let result = evaluateRange(value: 0.35, lower: 0.10, upper: 0.30, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.reasonCode, "exceeds_upper")
    }

    func testRangeUpperOnlyNormal() {
        let result = evaluateRange(value: 0.05, lower: nil, upper: 0.10, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeUpperOnlyWarning() {
        let result = evaluateRange(value: 0.09, lower: nil, upper: 0.10, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .warning)
    }

    func testRangeUpperOnlyViolation() {
        let result = evaluateRange(value: 0.12, lower: nil, upper: 0.10, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.magnitude, 0.02)
    }

    func testRangeLowerOnlyNormal() {
        let result = evaluateRange(value: 30, lower: 25, upper: nil, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeLowerOnlyWarning() {
        let result = evaluateRange(value: 28, lower: 25, upper: nil, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .warning)
    }

    func testRangeLowerOnlyViolation() {
        let result = evaluateRange(value: 20, lower: 25, upper: nil, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.magnitude, 5.0)
    }

    func testRangeNoBounds() {
        let result = evaluateRange(value: 100, lower: nil, upper: nil, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeWarningRatioOneNoWarning() {
        let result = evaluateRange(value: 0.09, lower: nil, upper: 0.10, warningRatio: 1.0)
        XCTAssertEqual(result.zone, .normal)
    }

    // MARK: - Presence tests (9.2)

    func testPresenceFound() {
        let items = [RuleEngineTests.makeTestItem(category: "whole_grain")]
        let result = evaluatePresence(dailyItems: items, targetCategories: ["whole_grain"], inverse: false)
        XCTAssertEqual(result.zone, .normal)
    }

    func testPresenceMissing() {
        let items = [RuleEngineTests.makeTestItem(category: "other")]
        let result = evaluatePresence(dailyItems: items, targetCategories: ["whole_grain"], inverse: false)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.reasonCode, "category_missing")
    }

    func testPresenceInverseViolation() {
        let items = [RuleEngineTests.makeTestItem(category: "processed_meat")]
        let result = evaluatePresence(dailyItems: items, targetCategories: ["processed_meat"], inverse: true)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.reasonCode, "unwanted_category_present")
    }

    func testPresenceInverseNormal() {
        let items = [RuleEngineTests.makeTestItem(category: "vegetable")]
        let result = evaluatePresence(dailyItems: items, targetCategories: ["processed_meat"], inverse: true)
        XCTAssertEqual(result.zone, .normal)
    }

    func testPresenceNilCategory() {
        let items = [RuleEngineTests.makeTestItem(category: nil)]
        let result = evaluatePresence(dailyItems: items, targetCategories: ["whole_grain"], inverse: false)
        XCTAssertEqual(result.zone, .violation)
    }

    // MARK: - CountSkipped tests (9.2)

    func testCountSkippedNormal() {
        let result = evaluateCountSkipped(skippedCount: 0, warningThreshold: 1, violationThreshold: 4)
        XCTAssertEqual(result.zone, .normal)
    }

    func testCountSkippedWarning() {
        let result = evaluateCountSkipped(skippedCount: 2, warningThreshold: 1, violationThreshold: 4)
        XCTAssertEqual(result.zone, .warning)
    }

    func testCountSkippedViolation() {
        let result = evaluateCountSkipped(skippedCount: 5, warningThreshold: 1, violationThreshold: 4)
        XCTAssertEqual(result.zone, .violation)
    }

    // MARK: - Zone comparison tests (9.3)

    func testZoneOrdering() {
        XCTAssertTrue(RuleZone.normal < RuleZone.warning)
        XCTAssertTrue(RuleZone.warning < RuleZone.violation)
        XCTAssertTrue(RuleZone.normal < RuleZone.violation)
    }

    func testZoneWorst() {
        XCTAssertEqual(RuleZone.worst(.normal, .violation), .violation)
        XCTAssertEqual(RuleZone.worst(.normal, .warning), .warning)
        XCTAssertEqual(RuleZone.worst(.normal, .normal), .normal)
    }

    // MARK: - Percentage computation tests (9.4)

    func testFatPercent() {
        let value = RuleEngineTests.percentOfCalories(grams: 50, calPerGram: 9, totalCalories: 1000)
        XCTAssertEqual(value, 0.45, accuracy: 0.001)
    }

    func testProteinPercent() {
        let value = RuleEngineTests.percentOfCalories(grams: 25, calPerGram: 4, totalCalories: 1000)
        XCTAssertEqual(value, 0.10, accuracy: 0.001)
    }

    func testSugarPercent() {
        let value = RuleEngineTests.percentOfCalories(grams: 10, calPerGram: 4, totalCalories: 1000)
        XCTAssertEqual(value, 0.04, accuracy: 0.001)
    }

    func testZeroCaloriesReturnsZero() {
        XCTAssertEqual(RuleEngineTests.percentOfCalories(grams: 10, calPerGram: 9, totalCalories: 0), 0)
    }

    // MARK: - JSON validation tests (9.5)

    func testValidRangeRule() {
        let json = """
        {"id":"test","type":"range","field":"fatPercent","params":{"lower":0.15,"upper":0.30},"warningRatio":0.85,"category":"test","title":"Test","description":"Desc","window":"day","minDaysData":3}
        """
        let rule = try? JSONDecoder().decode(RuleDefinition.self, from: Data(json.utf8))
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.id, "test")
        XCTAssertEqual(rule?.params.lower, 0.15)
        XCTAssertEqual(rule?.params.upper, 0.30)
    }

    func testValidPresenceRule() {
        let json = """
        {"id":"test","type":"presence","field":null,"params":{"category":"whole_grain"},"warningRatio":0.85,"category":"test","title":"Test","description":"Desc","window":"day","minDaysData":3}
        """
        let rule = try? JSONDecoder().decode(RuleDefinition.self, from: Data(json.utf8))
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.params.category, "whole_grain")
    }

    func testMissingOptionalFields() {
        let json = """
        {"id":"test","type":"range","field":"fatPercent","params":{},"warningRatio":0.85,"category":"test","title":"Test","description":"Desc","window":"day","minDaysData":3}
        """
        let rule = try? JSONDecoder().decode(RuleDefinition.self, from: Data(json.utf8))
        XCTAssertNotNil(rule)
        XCTAssertNil(rule?.params.lower)
        XCTAssertNil(rule?.params.upper)
    }

    // MARK: - Incremental calculation tests (9.6)

    @MainActor
    func testFullRebuildCreatesViolations() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = RuleEngine()
        engine.configure(context: context)

        let event = MealEvent(windowLabel: "Завтрак", status: .structured)
        event.calories = 1000
        event.fats = 50
        event.carbs = 0
        let item = EstimateItem(
            name: "Жирная еда",
            estimatedCalories: 1000,
            estimatedProteins: 0,
            estimatedFats: 50,
            estimatedCarbs: 0,
            impactScore: 0.5,
            reason: "",
            highCalorieFlag: false,
            sourceMode: .ingredientBreakdown,
            grams: 200
        )
        item.mealEvent = event
        context.insert(item)
        context.insert(event)
        try context.save()

        engine.fullRebuild(for: Date())

        let violations = engine.violationsForMeal(event)
        let fatViolation = violations.first { $0.ruleId == "who_total_fat" }
        XCTAssertNotNil(fatViolation, "Should have fat violation when fat is 45%")
        XCTAssertEqual(fatViolation?.zone, "violation")
    }

    @MainActor
    func testWeekResetRemovesOldViolations() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let engine = RuleEngine()
        engine.configure(context: context)

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

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MealEvent.self,
            EstimateItem.self,
            MealWindow.self,
            NutritionRuleConfig.self,
            RuleViolation.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    static func makeTestItem(category: String?) -> EstimateItem {
        EstimateItem(
            name: "test",
            estimatedCalories: 100,
            estimatedProteins: 5,
            estimatedFats: 5,
            estimatedCarbs: 10,
            impactScore: 0.5,
            reason: "",
            highCalorieFlag: false,
            sourceMode: .ingredientBreakdown,
            grams: 100,
            foodCategory: category
        )
    }

    static func percentOfCalories(grams: Double, calPerGram: Double, totalCalories: Double) -> Double {
        guard totalCalories > 0 else { return 0 }
        return (grams * calPerGram) / totalCalories
    }
}
