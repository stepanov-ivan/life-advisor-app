import SwiftUI
import SwiftData

struct StructuredIngredientDraft: Identifiable {
    let id = UUID()
    let name: String
    let amount: Double
    let unit: String
    let calories: Double
    let proteins: Double
    let fats: Double
    let carbs: Double
}

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealWindow.order) private var windows: [MealWindow]
    @State private var selectedSlotWindow: String?
    @State private var editingEvent: MealEvent?
    @State private var logText = ""
    @StateObject private var notificationManager = NotificationManager.shared

    var todayEvents: [MealEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let descriptor = FetchDescriptor<MealEvent>(
            predicate: #Predicate { $0.timestamp >= startOfDay }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var todayRecommendation: Recommendation? {
        let dateKey = DailyAdvice.dateKey(from: Date())
        let descriptor = FetchDescriptor<Recommendation>(
            predicate: #Predicate { $0.date == dateKey }
        )
        return try? modelContext.fetch(descriptor).first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DisclosureGroup("Питание") {
                        ForEach(windows.sorted(by: { $0.order < $1.order })) { window in
                            MealSlotCard(
                                windowLabel: window.name,
                                timeRange: "\(window.startTimeString)–\(window.endTimeString)",
                                event: todayEvents.first(where: { $0.windowLabel == window.name }),
                                recommendationText: todayRecommendation?.recommendationText,
                                recommendationEnabled: canRequestRecommendation(for: window.name),
                                onTap: { event in
                                    if let event {
                                        editingEvent = event
                                    } else {
                                        selectedSlotWindow = window.name
                                        logText = ""
                                    }
                                },
                                onRequestRecommendation: {
                                    requestRecommendation(for: window.name)
                                }
                            )
                        }
                    }
                    .padding(.horizontal)

                    actionButtons
                }
                .padding(.vertical)
            }
            .navigationTitle("Дашборд")
            .onChange(of: notificationManager.pendingLogWindow) { _, windowLabel in
                guard let windowLabel else { return }
                selectedSlotWindow = windowLabel
                logText = ""
                notificationManager.pendingLogWindow = nil
            }
            .onChange(of: notificationManager.pendingSkipWindow) { _, windowLabel in
                guard let windowLabel else { return }
                createSkippedEvent(windowLabel: windowLabel)
                notificationManager.pendingSkipWindow = nil
            }
            .sheet(item: selectedSlotWindowBinding) { windowLabel in
                LogSheetView(
                    windowLabel: windowLabel,
                    logText: $logText,
                    onSaveRaw: {
                        saveMealEvent(windowLabel: windowLabel)
                        selectedSlotWindow = nil
                    },
                    onSaveStructured: { ingredients in
                        saveStructuredEvent(windowLabel: windowLabel, ingredients: ingredients)
                        selectedSlotWindow = nil
                    }
                )
            }
            .sheet(item: $editingEvent) { event in
                MealEventEditorView(event: event)
            }
        }
    }

    private var selectedSlotWindowBinding: Binding<String?> {
        Binding(
            get: { selectedSlotWindow },
            set: { selectedSlotWindow = $0 }
        )
    }

    @ViewBuilder
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                processAllRawEvents()
            } label: {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Обработать всё")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(hasRawEvents ? Color.orange : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!hasRawEvents)

            Button {
                requestDailyAdvice()
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Совет дня")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canGetAdvice ? Color.green : Color.gray.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!canGetAdvice)
        }
        .padding(.horizontal)
    }

    private var hasRawEvents: Bool {
        todayEvents.contains { $0.status == .raw }
    }

    private var canGetAdvice: Bool {
        let relevantWindows = windows.map(\.name)
        let relevantEvents = todayEvents.filter { relevantWindows.contains($0.windowLabel) }

        for window in relevantWindows {
            guard let event = relevantEvents.first(where: { $0.windowLabel == window }) else {
                return false
            }
            if event.status != .structured && event.status != .skipped {
                return false
            }
        }

        return !relevantWindows.isEmpty
    }

    private func canRequestRecommendation(for windowLabel: String) -> Bool {
        let currentEvent = todayEvents.first(where: { $0.windowLabel == windowLabel })
        guard currentEvent == nil || currentEvent?.status == .empty else {
            return false
        }
        return todayEvents.contains { $0.status == .structured }
    }

    private func saveMealEvent(windowLabel: String) {
        let text = logText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        clearRecommendationCacheForToday()

        let event = MealEvent(
            windowLabel: windowLabel,
            status: .raw,
            rawText: text
        )
        modelContext.insert(event)
        try? modelContext.save()

        Task {
            await structurizeEvent(event)
        }
    }

    private func saveStructuredEvent(windowLabel: String, ingredients: [StructuredIngredientDraft]) {
        guard !ingredients.isEmpty else { return }

        clearRecommendationCacheForToday()

        let event = MealEvent(windowLabel: windowLabel, status: .structured)
        modelContext.insert(event)

        for item in ingredients {
            let ingredient = Ingredient(
                name: item.name,
                amount: item.amount,
                unit: item.unit,
                calories: item.calories,
                proteins: item.proteins,
                fats: item.fats,
                carbs: item.carbs
            )
            ingredient.mealEvent = event
            modelContext.insert(ingredient)
        }

        event.recalculateAggregates()
        try? modelContext.save()
    }

    private func clearRecommendationCacheForToday() {
        let dateKey = DailyAdvice.dateKey(from: Date())
        let descriptor = FetchDescriptor<Recommendation>(
            predicate: #Predicate { $0.date == dateKey }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try? modelContext.save()
        }
    }

    private func createSkippedEvent(windowLabel: String) {
        let existing = todayEvents.first(where: { $0.windowLabel == windowLabel })
        guard existing == nil else { return }

        clearRecommendationCacheForToday()

        let event = MealEvent(
            windowLabel: windowLabel,
            status: .skipped
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    private func structurizeEvent(_ event: MealEvent) async {
        guard let text = event.rawText else { return }

        do {
            let results = try await LLMClient.structurize(text: text)

            for item in results {
                let foodItem = findFoodItem(name: item.name)
                let ingredient = Ingredient(
                    name: item.name,
                    amount: item.amount,
                    unit: item.unit,
                    calories: (foodItem?.calories ?? 0) * item.amount / 100,
                    proteins: (foodItem?.proteins ?? 0) * item.amount / 100,
                    fats: (foodItem?.fats ?? 0) * item.amount / 100,
                    carbs: (foodItem?.carbs ?? 0) * item.amount / 100
                )
                ingredient.mealEvent = event
                modelContext.insert(ingredient)
            }

            event.recalculateAggregates()
            event.status = .structured
            try modelContext.save()
        } catch {
            print("Structurize error: \(error)")
        }
    }

    private func findFoodItem(name: String) -> FoodItem? {
        var descriptor = FetchDescriptor<FoodItem>(
            predicate: #Predicate { $0.name.localizedStandardContains(name) }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func processAllRawEvents() {
        let rawEvents = todayEvents.filter { $0.status == .raw }
        guard !rawEvents.isEmpty else { return }

        Task {
            let texts = rawEvents.compactMap(\.rawText)
            do {
                let results = try await LLMClient.batchStructurize(texts: texts)
                for (index, event) in rawEvents.enumerated() {
                    guard index < results.count else { break }
                    for item in results[index] {
                        let foodItem = findFoodItem(name: item.name)
                        let ingredient = Ingredient(
                            name: item.name,
                            amount: item.amount,
                            unit: item.unit,
                            calories: (foodItem?.calories ?? 0) * item.amount / 100,
                            proteins: (foodItem?.proteins ?? 0) * item.amount / 100,
                            fats: (foodItem?.fats ?? 0) * item.amount / 100,
                            carbs: (foodItem?.carbs ?? 0) * item.amount / 100
                        )
                        ingredient.mealEvent = event
                        modelContext.insert(ingredient)
                    }
                    event.recalculateAggregates()
                    event.status = .structured
                }
                try modelContext.save()
            } catch {
                print("Batch structurize error: \(error)")
            }
        }
    }

    private func requestRecommendation(for windowLabel: String) {
        let relevantWindows = windows.map(\.name)
        let todayRelevantEvents = todayEvents.filter { relevantWindows.contains($0.windowLabel) }

        let eatenMeals = todayRelevantEvents
            .filter { $0.status == .structured }
            .map { ($0.windowLabel, $0.calories, $0.proteins, $0.fats, $0.carbs) }

        let remainingWindows = relevantWindows.filter { label in
            todayRelevantEvents.first(where: { $0.windowLabel == label }) == nil
        }

        guard eatenMeals.count > 0, remainingWindows.contains(windowLabel) else {
            return
        }

        let goalCalories = UserDefaults.standard.double(forKey: "goal_calories")

        Task {
            do {
                let text = try await LLMClient.recommendation(
                    eaten: eatenMeals,
                    remainingWindows: remainingWindows,
                    goalCalories: goalCalories
                )

                let dateKey = DailyAdvice.dateKey(from: Date())
                let descriptor = FetchDescriptor<Recommendation>(
                    predicate: #Predicate { $0.date == dateKey }
                )

                if let existing = try? modelContext.fetch(descriptor).first {
                    existing.recommendationText = text
                    existing.createdAt = Date()
                } else {
                    modelContext.insert(Recommendation(date: dateKey, recommendationText: text))
                }
                try modelContext.save()
            } catch {
                print("Recommendation error: \(error)")
            }
        }
    }

    private func requestDailyAdvice() {
        let goalCalories = UserDefaults.standard.double(forKey: "goal_calories")
        let relevantWindows = windows.map(\.name)
        let todayRelevantEvents = todayEvents.filter { relevantWindows.contains($0.windowLabel) }

        var meals: [(window: String, rawText: String?, ingredients: [LLMClient.IngredientResult], calories: Double, proteins: Double, fats: Double, carbs: Double)] = []
        var skippedWindows: [String] = []

        for window in relevantWindows {
            if let event = todayRelevantEvents.first(where: { $0.windowLabel == window }) {
                if event.status == .skipped {
                    skippedWindows.append(window)
                } else {
                    let ingredients: [LLMClient.IngredientResult] = event.ingredients.map {
                        LLMClient.IngredientResult(name: $0.name, amount: $0.amount, unit: $0.unit)
                    }
                    meals.append((
                        window: window,
                        rawText: event.rawText,
                        ingredients: ingredients,
                        calories: event.calories,
                        proteins: event.proteins,
                        fats: event.fats,
                        carbs: event.carbs
                    ))
                }
            }
        }

        Task {
            do {
                let advice = try await LLMClient.dailyAdvice(
                    meals: meals,
                    goalCalories: goalCalories,
                    skippedWindows: skippedWindows
                )

                let dateKey = DailyAdvice.dateKey(from: Date())

                if let existing = try? modelContext.fetch(
                    FetchDescriptor<DailyAdvice>(
                        predicate: #Predicate { $0.date == dateKey }
                    )
                ).first {
                    existing.adviceText = advice
                    existing.createdAt = Date()
                } else {
                    modelContext.insert(DailyAdvice(date: dateKey, adviceText: advice))
                }

                try modelContext.save()
            } catch {
                print("Daily advice error: \(error)")
            }
        }
    }
}

struct MealSlotCard: View {
    let windowLabel: String
    let timeRange: String
    let event: MealEvent?
    let recommendationText: String?
    let recommendationEnabled: Bool
    let onTap: (MealEvent?) -> Void
    let onRequestRecommendation: () -> Void

    @State private var selectedTab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(windowLabel)
                    .font(.headline)
                Spacer()
                Text(timeRange)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let event = event {
                Picker("", selection: $selectedTab) {
                    Text("Лог").tag(0)
                    Text("Рекомендация").tag(1)
                }
                .pickerStyle(.segmented)

                if selectedTab == 0 {
                    eventContent(event)
                } else {
                    recommendationContent
                }
            } else {
                emptyContent
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap(event)
        }
    }

    private var backgroundColor: Color {
        guard let event = event else { return Color.gray.opacity(0.15) }
        switch event.status {
        case .empty: return Color.gray.opacity(0.15)
        case .raw: return Color.yellow.opacity(0.2)
        case .structured: return Color.green.opacity(0.2)
        case .skipped: return Color.gray.opacity(0.15)
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        HStack {
            Image(systemName: "plus.circle")
                .foregroundColor(.secondary)
            Text("Записать приём пищи")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func eventContent(_ event: MealEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if event.status == .skipped {
                HStack {
                    Image(systemName: "slash.circle")
                        .foregroundColor(.secondary)
                    Text("Пропущено")
                        .foregroundColor(.secondary)
                }
            } else if event.status == .raw {
                HStack {
                    Text(event.rawText ?? "")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: "clock")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            } else if event.status == .structured {
                Text("\(Int(event.calories)) ккал")
                    .font(.title3.bold())
                Text("Б: \(Int(event.proteins))г  Ж: \(Int(event.fats))г  У: \(Int(event.carbs))г")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !event.ingredients.isEmpty {
                    Text(event.ingredients.map { $0.name }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var recommendationContent: some View {
        VStack(spacing: 8) {
            if let recommendationText, !recommendationText.isEmpty {
                Text(recommendationText)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Получите рекомендацию для оставшихся приёмов")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button {
                onRequestRecommendation()
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Получить рекомендацию")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(recommendationEnabled ? Color.blue.opacity(0.1) : Color.gray.opacity(0.2))
                .foregroundColor(recommendationEnabled ? .blue : .secondary)
                .cornerRadius(8)
            }
            .disabled(!recommendationEnabled)
        }
    }
}

struct MealEventEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.name) private var foodItems: [FoodItem]

    let event: MealEvent

    @State private var rawTextDraft: String = ""
    @State private var ingredientQuery = ""
    @State private var selectedFoodName = ""
    @State private var newAmount = "100"
    @State private var templateName = ""
    @State private var llmInputText = ""
    @State private var isProcessingLLM = false
    @State private var llmError = ""

    var body: some View {
        NavigationStack {
            Form {
                if event.status == .raw {
                    Section("Текст") {
                        TextField("Что съели?", text: $rawTextDraft, axis: .vertical)
                            .lineLimit(3...6)

                        Button("Сохранить") {
                            event.rawText = rawTextDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            try? modelContext.save()
                            dismiss()
                        }
                        .disabled(rawTextDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Section("Обработка LLM") {
                        TextField("Текст для структуризации", text: $llmInputText, axis: .vertical)
                            .lineLimit(3...6)
                        if !llmError.isEmpty {
                            Text(llmError)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        Button(isProcessingLLM ? "Обрабатываю..." : "Обработать") {
                            processLLMText()
                        }
                        .disabled(isProcessingLLM || llmInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if event.status == .structured {
                    Section("Переобработать через LLM") {
                        TextField("Текст для структуризации", text: $llmInputText, axis: .vertical)
                            .lineLimit(3...6)
                        if !llmError.isEmpty {
                            Text(llmError)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        Button(isProcessingLLM ? "Обрабатываю..." : "Обработать заново") {
                            processLLMText()
                        }
                        .disabled(isProcessingLLM || llmInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Section("Ингредиенты") {
                        if event.ingredients.isEmpty {
                            Text("Нет ингредиентов")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(event.ingredients) { ingredient in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(ingredient.name)
                                        Text("\(Int(ingredient.calories)) ккал")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    TextField("Кол-во", value: Binding(
                                        get: { ingredient.amount },
                                        set: { newValue in
                                            updateIngredient(ingredient, amount: newValue)
                                        }
                                    ), format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 64)
                                    Text(ingredient.unit)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .onDelete(perform: deleteIngredients)
                        }
                    }

                    Section("Добавить из справочника") {
                        TextField("Поиск", text: $ingredientQuery)

                        Picker("Продукт", selection: $selectedFoodName) {
                            Text("Выберите продукт").tag("")
                            ForEach(filteredFoods, id: \.name) { item in
                                Text(item.name).tag(item.name)
                            }
                        }

                        TextField("Количество", text: $newAmount)
                            .keyboardType(.decimalPad)

                        Button("Добавить") {
                            addIngredientFromFood()
                        }
                        .disabled(selectedFoodName.isEmpty || Double(newAmount) == nil)
                    }

                    Section("Шаблон") {
                        TextField("Название шаблона", text: $templateName)
                        Button("Сохранить как шаблон") {
                            saveAsTemplate()
                        }
                        .disabled(templateName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || event.ingredients.isEmpty)
                    }
                }

                if event.status == .skipped {
                    Section {
                        Text("Пропущенный приём не редактируется")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(event.windowLabel)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                rawTextDraft = event.rawText ?? ""
                llmInputText = event.rawText ?? ""
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private var filteredFoods: [FoodItem] {
        let q = ingredientQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Array(foodItems.prefix(30)) }
        return foodItems.filter { $0.name.localizedCaseInsensitiveContains(q) }.prefix(30).map { $0 }
    }

    private func updateIngredient(_ ingredient: Ingredient, amount: Double) {
        guard let food = foodItems.first(where: { $0.name.localizedCaseInsensitiveContains(ingredient.name) }) else {
            ingredient.amount = amount
            event.recalculateAggregates()
            try? modelContext.save()
            return
        }

        ingredient.amount = amount
        ingredient.calories = food.calories * amount / 100
        ingredient.proteins = food.proteins * amount / 100
        ingredient.fats = food.fats * amount / 100
        ingredient.carbs = food.carbs * amount / 100
        event.recalculateAggregates()
        try? modelContext.save()
    }

    private func deleteIngredients(at offsets: IndexSet) {
        for index in offsets {
            let ingredient = event.ingredients[index]
            modelContext.delete(ingredient)
        }
        event.recalculateAggregates()
        try? modelContext.save()
    }

    private func addIngredientFromFood() {
        guard
            let food = foodItems.first(where: { $0.name == selectedFoodName }),
            let amount = Double(newAmount)
        else {
            return
        }

        let ingredient = Ingredient(
            name: food.name,
            amount: amount,
            unit: "г",
            calories: food.calories * amount / 100,
            proteins: food.proteins * amount / 100,
            fats: food.fats * amount / 100,
            carbs: food.carbs * amount / 100
        )
        ingredient.mealEvent = event
        modelContext.insert(ingredient)
        event.recalculateAggregates()
        try? modelContext.save()

        selectedFoodName = ""
        newAmount = "100"
    }

    private func saveAsTemplate() {
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let descriptor = FetchDescriptor<MealTemplate>(
            predicate: #Predicate { $0.name == name }
        )

        let template: MealTemplate
        if let existing = try? modelContext.fetch(descriptor).first {
            for ingredient in existing.ingredients {
                modelContext.delete(ingredient)
            }
            template = existing
        } else {
            template = MealTemplate(name: name)
            modelContext.insert(template)
        }

        for source in event.ingredients {
            let copy = TemplateIngredient(
                name: source.name,
                amount: source.amount,
                unit: source.unit,
                calories: source.calories,
                proteins: source.proteins,
                fats: source.fats,
                carbs: source.carbs
            )
            copy.template = template
            modelContext.insert(copy)
        }

        try? modelContext.save()
    }

    private func processLLMText() {
        let text = llmInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isProcessingLLM = true
        llmError = ""

        Task {
            do {
                let items = try await LLMClient.structurize(text: text)
                await MainActor.run {
                    for ingredient in event.ingredients {
                        modelContext.delete(ingredient)
                    }

                    for item in items {
                        let food = findFoodItem(name: item.name)
                        let ingredient = Ingredient(
                            name: item.name,
                            amount: item.amount,
                            unit: item.unit,
                            calories: (food?.calories ?? 0) * item.amount / 100,
                            proteins: (food?.proteins ?? 0) * item.amount / 100,
                            fats: (food?.fats ?? 0) * item.amount / 100,
                            carbs: (food?.carbs ?? 0) * item.amount / 100
                        )
                        ingredient.mealEvent = event
                        modelContext.insert(ingredient)
                    }

                    event.rawText = text
                    event.status = .structured
                    event.recalculateAggregates()
                    try? modelContext.save()
                    isProcessingLLM = false
                    llmInputText = text
                }
            } catch {
                await MainActor.run {
                    llmError = error.localizedDescription
                    isProcessingLLM = false
                }
            }
        }
    }

    private func findFoodItem(name: String) -> FoodItem? {
        foodItems.first { item in
            item.name.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains(item.name)
        }
    }
}

struct LogSheetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MealEvent.timestamp, order: .reverse) private var recentEvents: [MealEvent]
    @Query(sort: \MealTemplate.name) private var templates: [MealTemplate]

    let windowLabel: String
    @Binding var logText: String
    let onSaveRaw: () -> Void
    let onSaveStructured: ([StructuredIngredientDraft]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Лог") {
                    TextField("Что съели?", text: $logText, axis: .vertical)
                        .lineLimit(4...8)

                    Button("Готово") {
                        onSaveRaw()
                        dismiss()
                    }
                    .disabled(logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Из истории") {
                    if historyCandidates.isEmpty {
                        Text("Нет сохранённых приёмов")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(historyCandidates) { event in
                            Button {
                                let copied = event.ingredients.map {
                                    StructuredIngredientDraft(
                                        name: $0.name,
                                        amount: $0.amount,
                                        unit: $0.unit,
                                        calories: $0.calories,
                                        proteins: $0.proteins,
                                        fats: $0.fats,
                                        carbs: $0.carbs
                                    )
                                }
                                onSaveStructured(copied)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.windowLabel)
                                        .font(.subheadline.bold())
                                    Text(event.ingredients.map { $0.name }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                Section("Шаблоны") {
                    if templates.isEmpty {
                        Text("Нет шаблонов")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(templates) { template in
                            Button {
                                let copied = template.ingredients.map {
                                    StructuredIngredientDraft(
                                        name: $0.name,
                                        amount: $0.amount,
                                        unit: $0.unit,
                                        calories: $0.calories,
                                        proteins: $0.proteins,
                                        fats: $0.fats,
                                        carbs: $0.carbs
                                    )
                                }
                                onSaveStructured(copied)
                                dismiss()
                            } label: {
                                Text(template.name)
                            }
                        }
                    }
                }
            }
            .navigationTitle(windowLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private var historyCandidates: [MealEvent] {
        recentEvents
            .filter { $0.status == .structured && !$0.ingredients.isEmpty }
            .prefix(5)
            .map { $0 }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
