import Foundation

enum LLMClient {
    struct MealScenarioClassificationResult: Decodable {
        let scenario: String
        let dayOffset: Int?

        enum CodingKeys: String, CodingKey {
            case scenario
            case dayOffset = "day_offset"
        }
    }

    struct MealPlanningStepResult: Decodable {
        let type: String
        let dayOffset: Int?
        let mealSlot: String
        let title: String?
        let products: [EstimateItemResult]

        enum CodingKeys: String, CodingKey {
            case type
            case dayOffset = "day_offset"
            case mealSlot = "meal_slot"
            case title
            case products
        }
    }

    struct MealPlanningResult: Decodable {
        let scenario: String
        let steps: [MealPlanningStepResult]
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let responseFormat: ResponseFormat?

        struct Message: Encodable {
            let role: String
            let content: String
        }

        struct ResponseFormat: Encodable {
            let type: String
        }

        init(model: String, messages: [Message], temperature: Double = 0.3, jsonMode: Bool = false) {
            self.model = model
            self.messages = messages
            self.temperature = temperature
            self.responseFormat = jsonMode ? ResponseFormat(type: "json_object") : nil
        }
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message

            struct Message: Decodable {
                let content: String
            }
        }
    }

    struct Totals: Decodable {
        let calories: Double
        let proteins: Double
        let fats: Double
        let carbs: Double
        let saturatedFats: Double?
        let sugar: Double?
        let fiber: Double?
        let sodium: Double?

        enum CodingKeys: String, CodingKey {
            case calories, proteins, fats, carbs, sugar, fiber, sodium
            case saturatedFats = "saturated_fats"
        }

        init(
            calories: Double,
            proteins: Double,
            fats: Double,
            carbs: Double,
            saturatedFats: Double? = nil,
            sugar: Double? = nil,
            fiber: Double? = nil,
            sodium: Double? = nil
        ) {
            self.calories = calories
            self.proteins = proteins
            self.fats = fats
            self.carbs = carbs
            self.saturatedFats = saturatedFats
            self.sugar = sugar
            self.fiber = fiber
            self.sodium = sodium
        }
    }

    struct EstimateItemResult: Decodable {
        let name: String
        let grams: Double
        let estimatedCalories: Double
        let estimatedProteins: Double
        let estimatedFats: Double
        let estimatedCarbs: Double
        let impactScore: Double
        let reason: String
        let highCalorieFlag: Bool
        let saturatedFats: Double?
        let sugar: Double?
        let fiber: Double?
        let sodium: Double?
        let foodCategory: String?

        enum CodingKeys: String, CodingKey {
            case name, grams, estimatedCalories, estimatedProteins, estimatedFats, estimatedCarbs, reason, sugar, fiber, sodium
            case impactScore = "impact_score"
            case highCalorieFlag = "high_calorie_flag"
            case saturatedFats = "saturated_fats"
            case foodCategory = "food_category"
        }

        init(
            name: String,
            grams: Double,
            estimatedCalories: Double,
            estimatedProteins: Double,
            estimatedFats: Double,
            estimatedCarbs: Double,
            impactScore: Double,
            reason: String,
            highCalorieFlag: Bool = false,
            saturatedFats: Double? = nil,
            sugar: Double? = nil,
            fiber: Double? = nil,
            sodium: Double? = nil,
            foodCategory: String? = nil
        ) {
            self.name = name
            self.grams = grams
            self.estimatedCalories = estimatedCalories
            self.estimatedProteins = estimatedProteins
            self.estimatedFats = estimatedFats
            self.estimatedCarbs = estimatedCarbs
            self.impactScore = impactScore
            self.reason = reason
            self.highCalorieFlag = highCalorieFlag
            self.saturatedFats = saturatedFats
            self.sugar = sugar
            self.fiber = fiber
            self.sodium = sodium
            self.foodCategory = foodCategory
        }

        var clampedImpactScore: Double { min(1, max(0, impactScore)) }

        var validFoodCategory: String? {
            guard let cat = foodCategory else { return nil }
            let valid = ["fruit", "vegetable", "whole_grain", "legume", "nut_seed", "red_meat", "processed_meat", "other"]
            return valid.contains(cat) ? cat : "other"
        }
    }

    struct EstimationResult: Decodable {
        let mode: String
        let totals: Totals
        let confidence: String
        let items: [EstimateItemResult]
        let assumptions: [String]?
        let modelId: String
        let promptVersion: String
        let estimationSchemaVersion: String

        enum CodingKeys: String, CodingKey {
            case mode, totals, confidence, items, assumptions, modelId, promptVersion, estimationSchemaVersion
        }

        func validate() throws {
            guard ["ingredient_breakdown", "composite_item"].contains(mode) else {
                throw LLMError.parseError("Unknown mode")
            }
            guard ["low", "medium", "high"].contains(confidence) else {
                throw LLMError.parseError("Unknown confidence")
            }
            guard !items.isEmpty else {
                throw LLMError.parseError("Items must not be empty")
            }
            let namePortionPattern = #"\d+(?:[.,]\d+)?\s*(г|гр|грамм(?:а|ов)?|кг|мл|ml|л|литр(?:а|ов)?|шт|штук(?:и)?)|[()~]"#
            for item in items {
                guard item.grams > 0 else {
                    throw LLMError.parseError("Invalid grams in item: \(item.name)")
                }
                let trimmedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedName.isEmpty else {
                    throw LLMError.parseError("Empty item name")
                }
                if trimmedName.range(of: namePortionPattern, options: .regularExpression) != nil {
                    throw LLMError.parseError("Item name must be clean without portion markers: \(item.name)")
                }
            }
            if mode == "ingredient_breakdown" {
                let sumCalories = items.reduce(0) { $0 + $1.estimatedCalories }
                let sumProteins = items.reduce(0) { $0 + $1.estimatedProteins }
                let sumFats = items.reduce(0) { $0 + $1.estimatedFats }
                let sumCarbs = items.reduce(0) { $0 + $1.estimatedCarbs }
                guard withinTolerance(sumCalories, totals.calories),
                      withinTolerance(sumProteins, totals.proteins),
                      withinTolerance(sumFats, totals.fats),
                      withinTolerance(sumCarbs, totals.carbs)
                else {
                    throw LLMError.parseError("Breakdown totals mismatch")
                }
            }
        }

        private func withinTolerance(_ lhs: Double, _ rhs: Double) -> Bool {
            let base = max(1, abs(rhs))
            return abs(lhs - rhs) / base <= 0.05
        }
    }

    static var endpoint: String {
        UserDefaults.standard.string(forKey: "llm_endpoint") ?? ""
    }

    static var model: String {
        UserDefaults.standard.string(forKey: "llm_model") ?? ""
    }

    static var apiKey: String {
        KeychainHelper.read(key: "llm_api_key") ?? ""
    }

    static var requestTimeout: TimeInterval {
        let configured = UserDefaults.standard.double(forKey: "llm_timeout_seconds")
        return configured > 0 ? configured : 90
    }

    static var isConfigured: Bool {
        !endpoint.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }

    static func chat(userMessage: String, systemPrompt: String, jsonMode: Bool = false) async throws -> String {
        guard isConfigured else {
            throw LLMError.notConfigured
        }

        let messages = [
            ChatRequest.Message(role: "system", content: systemPrompt),
            ChatRequest.Message(role: "user", content: userMessage)
        ]

        let request = ChatRequest(
            model: model,
            messages: messages,
            temperature: 0.3,
            jsonMode: jsonMode
        )

        guard let base = URL(string: endpoint) else {
            throw LLMError.parseError("Invalid endpoint")
        }
        let url = base.appending(path: "chat/completions")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = requestTimeout
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw LLMError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.serverError(httpResponse.statusCode)
        }

        let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chatResponse.choices.first?.message.content else {
            throw LLMError.emptyResponse
        }

        return content
    }

    static func estimateMeal(text: String) async throws -> (parsed: EstimationResult, rawPayload: String) {
        let builder = PromptBuilder(language: AppLanguageManager.currentEffectiveLanguage)
        let systemPrompt = builder.mealEstimationSystemPrompt() + "\n\nJSON Schema:\n" + builder.mealEstimationJSONSchema() + "\n\nRequirements: grams required, clean item names only, at least one item for composite_item."

        let response = try await chat(userMessage: text, systemPrompt: systemPrompt, jsonMode: true)
        guard let data = response.data(using: .utf8) else {
            throw LLMError.parseError("Response encoding")
        }

        let parsed = try JSONDecoder().decode(EstimationResult.self, from: data)
        try parsed.validate()
        return (parsed, response)
    }

    static func dailyAdvice(
        meals: [(window: String, calories: Double, proteins: Double, fats: Double, carbs: Double)],
        goalCalories: Double,
        skippedWindows: [String]
    ) async throws -> String {
        let builder = PromptBuilder(language: AppLanguageManager.currentEffectiveLanguage)
        let userMessage = builder.dailyAdviceUserMessage(
            goalCalories: goalCalories,
            meals: meals,
            skippedWindows: skippedWindows
        )
        return try await chat(userMessage: userMessage, systemPrompt: builder.dailyAdviceSystemPrompt())
    }

    static func recommendation(
        eaten: [(window: String, calories: Double, proteins: Double, fats: Double, carbs: Double)],
        remainingWindows: [String],
        goalCalories: Double
    ) async throws -> String {
        let builder = PromptBuilder(language: AppLanguageManager.currentEffectiveLanguage)
        let userMessage = builder.recommendationUserMessage(
            goalCalories: goalCalories,
            eaten: eaten,
            remainingWindows: remainingWindows
        )
        return try await chat(userMessage: userMessage, systemPrompt: builder.dailyAdviceSystemPrompt())
    }

    static func classifyMealScenario(
        message: String,
        selectedDate: Date,
        dayEvents: [MealEvent]
    ) async throws -> MealScenarioClassification? {
        let dayContext = dayEvents.map {
            "\($0.windowLabel): \($0.rawText ?? "") \(Int($0.calories)) kcal"
        }.joined(separator: "\n")

        let systemPrompt = """
        Ты классифицируешь запросы про приёмы пищи для iOS приложения.
        Верни только JSON вида:
        {
          "scenario": "meal-create|meal-edit",
          "day_offset": -1|0|1
        }
        Используй:
        - meal-create, если пользователь описывает новую еду или логирование еды
        - meal-edit, если пользователь хочет изменить, убрать, исправить или дополнить существующую запись
        day_offset:
        - -1 для вчера
        - 0 для сегодня или текущего выбранного дня
        - 1 для завтра
        Не добавляй текст вне JSON.
        """

        let userMessage = """
        Selected day: \(DashboardDateLogic.dayKey(for: selectedDate))
        Existing day context:
        \(dayContext.isEmpty ? "none" : dayContext)

        User message:
        \(message)
        """

        let response = try await chat(userMessage: userMessage, systemPrompt: systemPrompt, jsonMode: true)
        guard let data = response.data(using: .utf8) else { return nil }
        let parsed = try JSONDecoder().decode(MealScenarioClassificationResult.self, from: data)
        guard let scenario = MealScenario(rawValue: parsed.scenario) else { return nil }
        let day = DashboardDateLogic.startOfDay(
            Calendar.current.date(byAdding: .day, value: clampedPlannerDayOffset(parsed.dayOffset), to: selectedDate) ?? selectedDate
        )
        return MealScenarioClassification(scenario: scenario, resolvedDay: day)
    }

    static func planMealExecution(
        message: String,
        scenario: MealScenario,
        selectedDate: Date,
        windows: [MealWindow],
        dayEvents: [MealEvent]
    ) async throws -> MealExecutionSession? {
        let systemPrompt = """
        Ты — роутер и планировщик meal flow в iOS приложении.
        Верни JSON с полями:
        {
          "scenario": "meal-create|meal-edit",
          "steps": [{
            "type": "create|edit",
            "day_offset": integer,
            "meal_slot": "breakfast|lunch|dinner",
            "title": "optional string",
            "products": [{
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
              "food_category": string|null
            }]
          }]
        }
        Не добавляй текст вне JSON. Строй только обоснованные шаги.
        """

        let dayContext = dayEvents.map {
            "\($0.windowLabel): \($0.rawText ?? "") \(Int($0.calories)) kcal"
        }.joined(separator: "\n")
        let windowsContext = windows.map { "\($0.windowId): \($0.localizedName())" }.joined(separator: "\n")
        let userMessage = """
        Scenario: \(scenario.rawValue)
        Selected day: \(DashboardDateLogic.dayKey(for: selectedDate))
        Windows:
        \(windowsContext)

        Existing day context:
        \(dayContext.isEmpty ? "none" : dayContext)

        User message:
        \(message)
        """

        let response = try await chat(userMessage: userMessage, systemPrompt: systemPrompt, jsonMode: true)
        guard let data = response.data(using: .utf8) else { return nil }
        let parsed = try JSONDecoder().decode(MealPlanningResult.self, from: data)
        let steps = parsed.steps.compactMap { step -> MealExecutionStep? in
            guard let type = MealStepType(rawValue: step.type) else { return nil }
            let day = Calendar.current.date(
                byAdding: .day,
                value: clampedPlannerDayOffset(step.dayOffset),
                to: selectedDate
            ) ?? selectedDate
            let title = step.title ?? windows.first(where: { $0.windowId == step.mealSlot })?.localizedName() ?? step.mealSlot
            let products = step.products.map {
                MealProductDraft(
                    name: $0.name,
                    grams: $0.grams,
                    estimatedCalories: $0.estimatedCalories,
                    estimatedProteins: $0.estimatedProteins,
                    estimatedFats: $0.estimatedFats,
                    estimatedCarbs: $0.estimatedCarbs,
                    impactScore: $0.impactScore,
                    reason: $0.reason,
                    saturatedFats: $0.saturatedFats ?? 0,
                    sugar: $0.sugar ?? 0,
                    fiber: $0.fiber ?? 0,
                    sodium: $0.sodium ?? 0,
                    foodCategory: $0.validFoodCategory
                )
            }
            return MealExecutionStep(
                type: type,
                day: day,
                windowId: step.mealSlot,
                title: title,
                products: products,
                sourceText: products.map(\.name).joined(separator: ", "),
                state: .readyForConfirm
            )
        }
        guard !steps.isEmpty else { return nil }
        return MealExecutionSession(scenario: scenario, originalMessage: message, steps: steps)
    }

    static func clampedPlannerDayOffset(_ offset: Int?) -> Int {
        min(1, max(-1, offset ?? 0))
    }
}

enum LLMError: Error, LocalizedError {
    case notConfigured
    case networkError
    case unauthorized
    case serverError(Int)
    case emptyResponse
    case parseError(String)

    var errorDescription: String? {
        PromptBuilder(language: AppLanguageManager.currentEffectiveLanguage).localizedLLMError(self)
    }
}
