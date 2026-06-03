import Foundation

enum LLMClient {
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
        let systemPrompt = """
        Ты — агент оценки питания. Верни ТОЛЬКО валидный JSON.
        Формат:
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
            "name": string,            // ТОЛЬКО чистое имя продукта/блюда без количества, скобок, тильды и служебных слов
            "grams": number,           // ОБЯЗАТЕЛЬНО > 0
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
          "promptVersion": "v3",
          "estimationSchemaVersion": "v3"
        }
        Дополнительные поля (опциональны, можно null):
        - saturated_fats: насыщенные жиры в граммах
        - sugar: свободный сахар в граммах
        - fiber: клетчатка в граммах
        - sodium: натрий в миллиграммах
        - food_category: категория продукта (fruit, vegetable, whole_grain, legume, nut_seed, red_meat, processed_meat, other)

        Для каждого item:
        1) grams обязателен, не пропускай.
        2) Если точная граммовка неизвестна, всё равно оцени и укажи grams.
        3) name должен быть чистым: "картофель", "минтай", "квашеная капуста".
           Нельзя: "3 средние картошки", "картошка (порция)", "~порция".
        Для composite_item верни минимум один item.
        """

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
        let mealsText = meals.map {
            "\($0.window): \(Int($0.calories)) ккал (Б:\(Int($0.proteins)) Ж:\(Int($0.fats)) У:\(Int($0.carbs)))"
        }.joined(separator: "\n")

        let skippedText = skippedWindows.isEmpty ? "" : "\nПропущенные приёмы: \(skippedWindows.joined(separator: ", "))"

        let userMessage = """
        Цель: \(Int(goalCalories)) ккал

        Съедено за день:
        \(mealsText)\(skippedText)

        Дай краткий совет дня.
        """

        return try await chat(userMessage: userMessage, systemPrompt: "Ты персональный диетолог")
    }

    static func recommendation(
        eaten: [(window: String, calories: Double, proteins: Double, fats: Double, carbs: Double)],
        remainingWindows: [String],
        goalCalories: Double
    ) async throws -> String {
        let eatenText = eaten.map {
            "\($0.window): \(Int($0.calories)) ккал (Б:\(Int($0.proteins)) Ж:\(Int($0.fats)) У:\(Int($0.carbs)))"
        }.joined(separator: "\n")

        let userMessage = """
        Цель: \(Int(goalCalories)) ккал
        Уже съедено:
        \(eatenText)
        Остались окна: \(remainingWindows.joined(separator: ", "))

        Дай рекомендацию по распределению калорий и БЖУ.
        """
        return try await chat(userMessage: userMessage, systemPrompt: "Ты персональный диетолог")
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
        switch self {
        case .notConfigured: return "LLM не настроен. Укажите endpoint, ключ и модель в настройках."
        case .networkError: return "Нет соединения с сервером."
        case .unauthorized: return "Ошибка авторизации. Проверьте API-ключ."
        case .serverError(let code): return "Ошибка сервера (\(code))."
        case .emptyResponse: return "Пустой ответ от LLM."
        case .parseError(let reason): return "Не удалось разобрать ответ LLM: \(reason)."
        }
    }
}
