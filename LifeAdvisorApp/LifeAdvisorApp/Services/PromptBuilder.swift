import Foundation

struct PromptBuilder {
    let language: AppLanguage

    func mealEstimationSystemPrompt() -> String {
        LocalizationHelper.localized("meal_estimation_system", table: "Prompts", language: language)
    }

    func mealEstimationJSONSchema() -> String {
        let schema = """
        {
          "mode": "ingredient_breakdown|composite_item",
          "totals": {
            "calories": number, "proteins": number, "fats": number, "carbs": number,
            "saturated_fats": number|null,
            "sugar": number|null,
            "fiber": number|null,
            "sodium": number|null
          },
          "confidence": "low|medium|high",
          "items": [{
            "name": string,
            "grams": number,
            "estimatedCalories": number,
            "estimatedProteins": number,
            "estimatedFats": number,
            "estimatedCarbs": number,
            "impact_score": number,
            "reason": string,
            "high_calorie_flag": bool,
            "saturated_fats": number|null,
            "sugar": number|null,
            "fiber": number|null,
            "sodium": number|null,
            "food_category": "fruit"|"vegetable"|"whole_grain"|"legume"|"nut_seed"|"red_meat"|"processed_meat"|"other"|null
          }],
          "assumptions": [string],
          "modelId": string,
          "promptVersion": "v4",
          "estimationSchemaVersion": "v4"
        }
        """
        return schema
    }

    func dailyAdviceUserMessage(
        goalCalories: Double,
        meals: [(window: String, calories: Double, proteins: Double, fats: Double, carbs: Double)],
        skippedWindows: [String]
    ) -> String {
        let template = LocalizationHelper.localized("daily_advice_user", table: "Prompts", language: language)
        var totalCal: Double = 0
        var totalProtein: Double = 0
        var totalFat: Double = 0
        var totalCarbs: Double = 0
        for meal in meals {
            totalCal += meal.calories
            totalProtein += meal.proteins
            totalFat += meal.fats
            totalCarbs += meal.carbs
        }
        let mealsText = meals.map {
            "\($0.window): \(Int($0.calories)) kcal (P:\(Int($0.proteins)) F:\(Int($0.fats)) C:\(Int($0.carbs)))"
        }.joined(separator: "\n")
        return String(format: template, mealsText, "\(Int(totalCal))", "\(Int(totalProtein))", "\(Int(totalFat))", "\(Int(totalCarbs))")
    }

    func dailyAdviceSystemPrompt() -> String {
        LocalizationHelper.localized("daily_advice_system", table: "Prompts", language: language)
    }

    func recommendationUserMessage(
        goalCalories: Double,
        eaten: [(window: String, calories: Double, proteins: Double, fats: Double, carbs: Double)],
        remainingWindows: [String]
    ) -> String {
        let template = LocalizationHelper.localized("recommendation_user", table: "Prompts", language: language)
        let eatenText = eaten.map {
            "\($0.window): \(Int($0.calories)) kcal (P:\(Int($0.proteins)) F:\(Int($0.fats)) C:\(Int($0.carbs)))"
        }.joined(separator: "\n")
        return String(format: template, eatenText, remainingWindows.joined(separator: ", "))
    }

    func localizedLLMError(_ error: LLMError) -> String {
        switch error {
        case .notConfigured:
            return LocalizationHelper.localized("llm_not_configured", table: "Prompts", language: language)
        case .networkError:
            return LocalizationHelper.localized("llm_network_error", table: "Prompts", language: language)
        case .unauthorized:
            return LocalizationHelper.localized("llm_unauthorized", table: "Prompts", language: language)
        case .serverError(let code):
            return String(format: LocalizationHelper.localized("llm_server_error", table: "Prompts", language: language)) + " (\(code))"
        case .emptyResponse:
            return LocalizationHelper.localized("llm_empty_response", table: "Prompts", language: language)
        case .parseError(let reason):
            return LocalizationHelper.localized("llm_parse_error", table: "Prompts", language: language) + ": \(reason)"
        }
    }
}
