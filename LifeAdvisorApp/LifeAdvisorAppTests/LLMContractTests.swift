import XCTest
@testable import LifeAdvisorApp

final class LLMContractTests: XCTestCase {
    func testSchemaValidationSucceedsForCompositeItem() throws {
        let json = """
        {
          \"mode\": \"composite_item\",
          \"totals\": {\"calories\": 500, \"proteins\": 20, \"fats\": 15, \"carbs\": 60},
          \"confidence\": \"medium\",
          \"items\": [{
            \"name\": \"Биг Тейсти\",
            \"quantity\": 1,
            \"unit\": \"pcs\",
            \"estimatedCalories\": 500,
            \"estimatedProteins\": 20,
            \"estimatedFats\": 15,
            \"estimatedCarbs\": 60,
            \"impact_score\": 0.8,
            \"reason\": \"Высокая калорийность\",
            \"high_calorie_flag\": true
          }],
          \"modelId\": \"model-x\",
          \"promptVersion\": \"v2\",
          \"estimationSchemaVersion\": \"v2\"
        }
        """

        let parsed = try JSONDecoder().decode(LLMClient.EstimationResult.self, from: Data(json.utf8))
        XCTAssertNoThrow(try parsed.validate())
    }

    func testSchemaValidationFailsForMissingItems() throws {
        let json = """
        {
          \"mode\": \"composite_item\",
          \"totals\": {\"calories\": 500, \"proteins\": 20, \"fats\": 15, \"carbs\": 60},
          \"confidence\": \"high\",
          \"items\": [],
          \"modelId\": \"model-x\",
          \"promptVersion\": \"v2\",
          \"estimationSchemaVersion\": \"v2\"
        }
        """

        let parsed = try JSONDecoder().decode(LLMClient.EstimationResult.self, from: Data(json.utf8))
        XCTAssertThrowsError(try parsed.validate())
    }

    func testSchemaValidationFailsForInvalidConfidence() throws {
        let json = """
        {
          \"mode\": \"composite_item\",
          \"totals\": {\"calories\": 500, \"proteins\": 20, \"fats\": 15, \"carbs\": 60},
          \"confidence\": \"certain\",
          \"items\": [{
            \"name\": \"Биг Тейсти\",
            \"quantity\": 1,
            \"unit\": \"pcs\",
            \"estimatedCalories\": 500,
            \"estimatedProteins\": 20,
            \"estimatedFats\": 15,
            \"estimatedCarbs\": 60,
            \"impact_score\": 0.8,
            \"reason\": \"ok\",
            \"high_calorie_flag\": true
          }],
          \"modelId\": \"model-x\",
          \"promptVersion\": \"v2\",
          \"estimationSchemaVersion\": \"v2\"
        }
        """

        let parsed = try JSONDecoder().decode(LLMClient.EstimationResult.self, from: Data(json.utf8))
        XCTAssertThrowsError(try parsed.validate())
    }

    func testIngredientBreakdownWithinTolerancePasses() throws {
        let json = """
        {
          \"mode\": \"ingredient_breakdown\",
          \"totals\": {\"calories\": 600, \"proteins\": 24, \"fats\": 22, \"carbs\": 55},
          \"confidence\": \"medium\",
          \"items\": [
            {\"name\": \"Биг Мак\", \"quantity\": 1, \"unit\": \"pcs\", \"estimatedCalories\": 500, \"estimatedProteins\": 20, \"estimatedFats\": 18, \"estimatedCarbs\": 45, \"impact_score\": 0.8, \"reason\": \"ok\", \"high_calorie_flag\": true},
            {\"name\": \"Штрудель\", \"quantity\": 150, \"unit\": \"g\", \"estimatedCalories\": 100, \"estimatedProteins\": 4, \"estimatedFats\": 4, \"estimatedCarbs\": 10, \"impact_score\": 0.4, \"reason\": \"ok\", \"high_calorie_flag\": false}
          ],
          \"modelId\": \"model-x\",
          \"promptVersion\": \"v2\",
          \"estimationSchemaVersion\": \"v2\"
        }
        """

        let parsed = try JSONDecoder().decode(LLMClient.EstimationResult.self, from: Data(json.utf8))
        XCTAssertNoThrow(try parsed.validate())
    }

    func testIngredientBreakdownBeyondToleranceFails() throws {
        let json = """
        {
          \"mode\": \"ingredient_breakdown\",
          \"totals\": {\"calories\": 1000, \"proteins\": 10, \"fats\": 10, \"carbs\": 10},
          \"confidence\": \"medium\",
          \"items\": [
            {\"name\": \"Биг Мак\", \"quantity\": 1, \"unit\": \"pcs\", \"estimatedCalories\": 500, \"estimatedProteins\": 20, \"estimatedFats\": 18, \"estimatedCarbs\": 45, \"impact_score\": 0.8, \"reason\": \"ok\", \"high_calorie_flag\": true}
          ],
          \"modelId\": \"model-x\",
          \"promptVersion\": \"v2\",
          \"estimationSchemaVersion\": \"v2\"
        }
        """

        let parsed = try JSONDecoder().decode(LLMClient.EstimationResult.self, from: Data(json.utf8))
        XCTAssertThrowsError(try parsed.validate())
    }

    func testSchemaValidationFailsForDirtyItemName() throws {
        let json = """
        {
          \"mode\": \"ingredient_breakdown\",
          \"totals\": {\"calories\": 600, \"proteins\": 24, \"fats\": 22, \"carbs\": 55},
          \"confidence\": \"medium\",
          \"items\": [
            {\"name\": \"3 средние картошки (порция)\", \"quantity\": 450, \"unit\": \"g\", \"estimatedCalories\": 400, \"estimatedProteins\": 8, \"estimatedFats\": 4, \"estimatedCarbs\": 78, \"impact_score\": 0.8, \"reason\": \"ok\", \"high_calorie_flag\": true},
            {\"name\": \"Минтай\", \"quantity\": 200, \"unit\": \"g\", \"estimatedCalories\": 200, \"estimatedProteins\": 16, \"estimatedFats\": 18, \"estimatedCarbs\": 0, \"impact_score\": 0.4, \"reason\": \"ok\", \"high_calorie_flag\": false}
          ],
          \"modelId\": \"model-x\",
          \"promptVersion\": \"v2\",
          \"estimationSchemaVersion\": \"v2\"
        }
        """

        let parsed = try JSONDecoder().decode(LLMClient.EstimationResult.self, from: Data(json.utf8))
        XCTAssertThrowsError(try parsed.validate())
    }
}
