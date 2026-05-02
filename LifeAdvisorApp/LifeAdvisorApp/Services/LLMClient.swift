import Foundation

enum LLMClient {
    private struct IngredientsEnvelope: Decodable {
        let ingredients: [IngredientResult]
    }

    private struct BatchIngredientsEnvelope: Decodable {
        let items: [[IngredientResult]]
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

            enum CodingKeys: String, CodingKey {
                case type
            }
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

    struct IngredientResult: Decodable {
        let name: String
        let amount: Double
        let unit: String
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

        var urlRequest = URLRequest(url: URL(string: "\(endpoint)/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 30
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

    static func structurize(text: String) async throws -> [IngredientResult] {
        let systemPrompt = """
        Ты — помощник по питанию. Извлеки из описания приёма пищи список ингредиентов
        с количеством и единицей измерения. Отвечай ТОЛЬКО валидным JSON-объектом:
        {"ingredients":[{"name": "название", "amount": число, "unit": "г/мл/шт"}]}
        Количество оценивай в граммах/миллилитрах. Будь консервативен в оценках порций.
        """

        let response = try await chat(
            userMessage: text,
            systemPrompt: systemPrompt,
            jsonMode: true
        )

        guard let data = response.data(using: .utf8) else {
            throw LLMError.parseError
        }

        if let ingredients = try? JSONDecoder().decode([IngredientResult].self, from: data) {
            return ingredients
        }

        if let wrapped = try? JSONDecoder().decode(IngredientsEnvelope.self, from: data) {
            return wrapped.ingredients
        }

        throw LLMError.parseError
    }

    static func batchStructurize(texts: [String]) async throws -> [[IngredientResult]] {
        let systemPrompt = """
        Ты — помощник по питанию. Извлеки из КАЖДОГО описания список ингредиентов.
        Отвечай ТОЛЬКО валидным JSON-объектом:
        {"items":[[{"name": "...", "amount": число, "unit": "г/мл/шт"}, ...], ...]}
        Каждый подмассив в items соответствует одному описанию в том же порядке.
        """

        let combined = texts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let response = try await chat(
            userMessage: combined,
            systemPrompt: systemPrompt,
            jsonMode: true
        )

        guard let data = response.data(using: .utf8) else {
            throw LLMError.parseError
        }

        if let results = try? JSONDecoder().decode([[IngredientResult]].self, from: data) {
            return results
        }

        if let wrapped = try? JSONDecoder().decode(BatchIngredientsEnvelope.self, from: data) {
            return wrapped.items
        }

        throw LLMError.parseError
    }

    static func dailyAdvice(
        meals: [(window: String, rawText: String?, ingredients: [IngredientResult], calories: Double, proteins: Double, fats: Double, carbs: Double)],
        goalCalories: Double,
        skippedWindows: [String]
    ) async throws -> String {
        var mealDescriptions = ""
        for meal in meals {
            let ingredientList = meal.ingredients.map { "\($0.name) \(Int($0.amount))\($0.unit)" }.joined(separator: ", ")
            mealDescriptions += """
            \(meal.window): \(ingredientList)
            Калории: \(Int(meal.calories)), Б: \(Int(meal.proteins))г, Ж: \(Int(meal.fats))г, У: \(Int(meal.carbs))г

            """
        }

        var skippedText = ""
        if !skippedWindows.isEmpty {
            skippedText = "\nПропущенные приёмы: \(skippedWindows.joined(separator: ", "))"
        }

        let systemPrompt = """
        Ты — персональный диетолог. Проанализируй питание за день и дай совет.
        Оцени: баланс БЖУ, качество продуктов (фастфуд, клетчатка, сахар, овощи),
        соответствие цели. Учитывай пропущенные приёмы.
        Дай практичные рекомендации на завтра. Будь поддерживающим, но честным.
        """

        let userMessage = """
        Цель: \(Int(goalCalories)) ккал

        Съедено за день:
        \(mealDescriptions)\(skippedText)

        Дай совет дня.
        """

        return try await chat(userMessage: userMessage, systemPrompt: systemPrompt)
    }

    static func recommendation(
        eaten: [(window: String, calories: Double, proteins: Double, fats: Double, carbs: Double)],
        remainingWindows: [String],
        goalCalories: Double
    ) async throws -> String {
        let eatenText = eaten.map {
            "\($0.window): \(Int($0.calories)) ккал (Б:\(Int($0.proteins)), Ж:\(Int($0.fats)), У:\(Int($0.carbs)))"
        }.joined(separator: "\n")

        let remainingText = remainingWindows.joined(separator: ", ")
        let remainingCalories = goalCalories - eaten.reduce(0) { $0 + $1.calories }

        let systemPrompt = """
        Ты — персональный диетолог. Распредели оставшиеся калории и БЖУ на оставшиеся приёмы.
        Дай конкретные рекомендации: сколько калорий на каждый приём,
        какой баланс БЖУ, какие продукты предпочесть.
        """

        let userMessage = """
        Цель: \(Int(goalCalories)) ккал
        Уже съедено:
        \(eatenText)
        Осталось: \(Int(max(0, remainingCalories))) ккал
        Оставшиеся приёмы: \(remainingText)

        Дай рекомендацию по распределению.
        """

        return try await chat(userMessage: userMessage, systemPrompt: systemPrompt)
    }
}

enum LLMError: Error, LocalizedError {
    case notConfigured
    case networkError
    case unauthorized
    case serverError(Int)
    case emptyResponse
    case parseError

    var errorDescription: String? {
        switch self {
        case .notConfigured: "LLM не настроен. Укажите endpoint, ключ и модель в настройках."
        case .networkError: "Нет соединения с сервером."
        case .unauthorized: "Ошибка авторизации. Проверьте API-ключ."
        case .serverError(let code): "Ошибка сервера (\(code))."
        case .emptyResponse: "Пустой ответ от LLM."
        case .parseError: "Не удалось разобрать ответ LLM."
        }
    }
}
