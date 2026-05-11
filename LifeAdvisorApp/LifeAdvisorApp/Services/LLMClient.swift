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
    }

    struct EstimateItemResult: Decodable {
        enum ItemUnit: String, Decodable {
            case g
            case ml
            case pcs

            var measureUnit: MeasureUnit {
                switch self {
                case .g: return .g
                case .ml: return .ml
                case .pcs: return .pcs
                }
            }
        }

        let name: String
        let quantity: Double
        let unitRaw: String
        let estimatedCalories: Double
        let estimatedProteins: Double
        let estimatedFats: Double
        let estimatedCarbs: Double
        let impactScore: Double
        let reason: String
        let highCalorieFlag: Bool

        enum CodingKeys: String, CodingKey {
            case name, quantity, estimatedCalories, estimatedProteins, estimatedFats, estimatedCarbs, reason
            case unitRaw = "unit"
            case impactScore = "impact_score"
            case highCalorieFlag = "high_calorie_flag"
        }

        var clampedImpactScore: Double { min(1, max(0, impactScore)) }
        var unit: MeasureUnit {
            ItemUnit(rawValue: unitRaw)?.measureUnit ?? .pcs
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
                guard item.quantity > 0 else {
                    throw LLMError.parseError("Invalid quantity in item: \(item.name)")
                }
                guard ["g", "ml", "pcs"].contains(item.unitRaw) else {
                    throw LLMError.parseError("Invalid unit in item: \(item.name)")
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
          "totals": {"calories": number, "proteins": number, "fats": number, "carbs": number},
          "confidence": "low|medium|high",
          "items": [{
            "name": string,            // ТОЛЬКО чистое имя продукта/блюда без количества, скобок, тильды и служебных слов
            "quantity": number,        // ОБЯЗАТЕЛЬНО > 0
            "unit": "g|ml|pcs",        // ОБЯЗАТЕЛЬНО
            "estimatedCalories": number,
            "estimatedProteins": number,
            "estimatedFats": number,
            "estimatedCarbs": number,
            "impact_score": number,
            "reason": string,
            "high_calorie_flag": bool
          }],
          "assumptions": [string],
          "modelId": string,
          "promptVersion": "v2",
          "estimationSchemaVersion": "v2"
        }
        Для каждого item:
        1) quantity и unit обязательны, не пропускай.
        2) Если точная граммовка неизвестна, всё равно оцени и укажи quantity в g/ml/pcs.
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
