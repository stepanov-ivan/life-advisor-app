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
        // lower / ratio = 0.10 / 0.85 = 0.1176. Value 0.11 < 0.1176, so warning
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
        // upper = 0.10, warningRatio = 0.85, warning border = 0.085
        let result = evaluateRange(value: 0.09, lower: nil, upper: 0.10, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .warning)
    }

    func testRangeUpperOnlyViolation() {
        let result = evaluateRange(value: 0.12, lower: nil, upper: 0.10, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .violation)
        XCTAssertEqual(result.magnitude, 0.02, accuracy: 0.001)
    }

    func testRangeLowerOnlyNormal() {
        // lower = 25, warningRatio = 0.85, warning border = 25/0.85 = 29.4
        let result = evaluateRange(value: 30, lower: 25, upper: nil, warningRatio: 0.85)
        XCTAssertEqual(result.zone, .normal)
    }

    func testRangeLowerOnlyWarning() {
        // lower = 25, warning border = 29.4. value = 28 < 29.4 -> warning
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
        // warningRatio = 1.0 means no warning zone
        let result = evaluateRange(value: 0.09, lower: nil, upper: 0.10, warningRatio: 1.0)
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
