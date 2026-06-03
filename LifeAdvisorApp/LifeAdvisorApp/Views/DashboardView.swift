import SwiftUI
import SwiftData

struct DashboardView: View {
    @Binding var selectedDate: Date

    struct ManualDraftStructure {
        struct DraftItem {
            var name: String
            var grams: Double
            var calories: Double
            var proteins: Double
            var fats: Double
            var carbs: Double
            var impactScore: Double
            var reason: String
            var saturatedFats: Double = 0
            var sugar: Double = 0
            var fiber: Double = 0
            var sodium: Double = 0
            var foodCategory: String? = nil
        }

        var calories: Double
        var proteins: Double
        var fats: Double
        var carbs: Double
        var source: StructureSource
        var sourceText: String
        var items: [DraftItem]
    }

    struct LogDraftResult {
        var text: String
        var draftStructure: ManualDraftStructure?
        var treatTextAsNote: Bool
        var keepStructureWithoutReestimate: Bool
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealWindow.order) private var windows: [MealWindow]
    @StateObject private var notificationManager = NotificationManager.shared
    @AppStorage("dashboard_last_selected_day") private var lastSelectedDayKey = ""
    @State private var ruleEngine = RuleEngine()

    @State private var selectedWindow: String?
    @State private var editingEvent: MealEvent?
    @State private var logText = ""
    @State private var showDatePicker = false
    @State private var showFutureDateHint = false

    var activeHypothesis: MemoryHypothesis? {
        MemoryEngine.activeHypothesisPrompt(context: modelContext)
    }

    var dayEvents: [MealEvent] {
        let range = DashboardDateLogic.dayRange(for: selectedDate)
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<MealEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\MealEvent.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var weekDates: [Date] {
        DashboardDateLogic.weekDates(around: selectedDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateNavigationRow
                        .padding(.horizontal)

                    if let hypothesis = activeHypothesis {
                        hypothesisPromptCard(hypothesis)
                            .padding(.horizontal)
                    }

                    DisclosureGroup("Питание") {
                        ForEach(windows) { window in
                            let event = latestEvent(for: window.name)
                            MealSlotCard(
                                windowLabel: window.name,
                                timeRange: "\(window.startTimeString)–\(window.endTimeString)",
                                event: event,
                                violations: event.flatMap { ruleEngine.violationsForMeal($0) } ?? [],
                                engine: ruleEngine,
                                onTap: {
                                    if let event {
                                        editingEvent = event
                                    } else {
                                        selectedWindow = window.name
                                        logText = ""
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)

                    DayAnalyticsPanel(
                        rules: ruleEngine.enabledRules(),
                        engine: ruleEngine,
                        date: selectedDate
                    )
                }
                .padding(.vertical)
            }
            .navigationTitle("Дашборд")
            .onAppear {
                restoreLastSelectedDate()
                ruleEngine.configure(context: modelContext)
                ruleEngine.resetWeekIfNeeded()
                ruleEngine.generateViolations(for: selectedDate)
            }
            .onChange(of: notificationManager.pendingLogWindow) { _, value in
                guard let value else { return }
                selectedWindow = value
                logText = ""
                notificationManager.pendingLogWindow = nil
            }
            .onChange(of: notificationManager.pendingSkipWindow) { _, value in
                guard let value else { return }
                createSkippedEvent(windowLabel: value)
                notificationManager.pendingSkipWindow = nil
            }
            .sheet(item: selectedWindowBinding) { window in
                LogSheetView(windowLabel: window, initialText: logText) { draft in
                    saveMealEvent(windowLabel: window, draft: draft)
                    selectedWindow = nil
                }
            }
            .sheet(item: $editingEvent) { event in
                MealEventEditorView(event: event, violations: ruleEngine.violationsForMeal(event))
            }
            .sheet(isPresented: $showDatePicker) {
                DatePickerSheet(
                    selectedDate: selectedDate,
                    onSelect: { date in
                        if isFutureDate(date) {
                            showFutureDateHint = true
                            return
                        }
                        applySelectedDate(date)
                    }
                )
            }
            .alert("Будущие даты недоступны", isPresented: $showFutureDateHint) {
                Button("OK", role: .cancel) { }
            }
        }
    }

    private var selectedWindowBinding: Binding<String?> {
        .init(get: { selectedWindow }, set: { selectedWindow = $0 })
    }

    @ViewBuilder
    private var dateNavigationRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.headline)
                Spacer()
                Button {
                    showDatePicker = true
                } label: {
                    Label("Календарь", systemImage: "calendar")
                }
                .buttonStyle(.bordered)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(weekDates, id: \.self) { day in
                        let disabled = isFutureDate(day)
                        Button {
                            if disabled {
                                showFutureDateHint = true
                            } else {
                                applySelectedDate(day)
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(day.formatted(.dateTime.weekday(.narrow)))
                                Text(day.formatted(.dateTime.day()))
                            }
                            .font(.caption)
                            .frame(width: 40, height: 40)
                            .background(isSameDay(day, selectedDate) ? Color.blue : Color.gray.opacity(0.15))
                            .foregroundColor(disabled ? .gray : (isSameDay(day, selectedDate) ? .white : .primary))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func saveMealEvent(windowLabel: String, draft: LogDraftResult) {
        let text = MemoryEngine.normalizeForSync(draft.text)
        guard text.count >= 3 else { return }

        let event: MealEvent
        if let existing = latestEvent(for: windowLabel) {
            event = existing
            event.rawText = text
            event.userNote = draft.treatTextAsNote ? text : nil
            event.status = .pendingEstimation
            event.structureSource = .llm
            event.outOfSync = false
            event.baselineTextNormalized = nil
            event.structureLastSyncedAt = nil
            event.parseErrorSummary = nil
            event.memoryApplied = false
            print("Meal upsert: update existing event for \(windowLabel), id=\(existing.persistentModelID)")
        } else {
            let created = MealEvent(
                windowLabel: windowLabel,
                timestamp: preferredTimestampForSelectedDay(),
                status: .pendingEstimation,
                rawText: text
            )
            created.structureSource = .llm
            created.userNote = draft.treatTextAsNote ? text : nil
            created.baselineTextNormalized = nil
            created.structureLastSyncedAt = nil
            modelContext.insert(created)
            event = created
            print("Meal upsert: create new event for \(windowLabel), id=\(created.persistentModelID)")
        }

        if let draftStructure = draft.draftStructure, draft.keepStructureWithoutReestimate {
            event.applyTotals(
                calories: draftStructure.calories,
                proteins: draftStructure.proteins,
                fats: draftStructure.fats,
                carbs: draftStructure.carbs
            )
            event.status = .structured
            event.structureSource = draftStructure.source
            event.outOfSync = MemoryEngine.isOutOfSync(
                selectedText: draftStructure.sourceText,
                currentText: text
            )
            event.baselineTextNormalized = MemoryEngine.normalizeForSync(draftStructure.sourceText)
            event.structureLastSyncedAt = Date()
            event.confidence = "medium"
            event.memoryApplied = draftStructure.source == .memorySuggestion
            let sourceMode: EstimateSourceMode = .compositeItem
            EstimationRuntime.overwriteSnapshot(
                event: event,
                with: draftStructure.items.map {
                    LLMClient.EstimateItemResult(
                        name: $0.name,
                        grams: $0.grams,
                        estimatedCalories: $0.calories,
                        estimatedProteins: $0.proteins,
                        estimatedFats: $0.fats,
                        estimatedCarbs: $0.carbs,
                        impactScore: $0.impactScore,
                        reason: $0.reason,
                        saturatedFats: $0.saturatedFats,
                        sugar: $0.sugar,
                        fiber: $0.fiber,
                        sodium: $0.sodium,
                        foodCategory: $0.foodCategory
                    )
                },
                mode: sourceMode.rawValue,
                modelContext: modelContext
            )
                    }
        try? modelContext.save()
        ruleEngine.generateViolations(for: selectedDate)

        if draft.draftStructure != nil && draft.keepStructureWithoutReestimate {
            MemoryEngine.upsertPrimarySuggestion(
                text: text,
                totals: (
                    calories: event.calories,
                    proteins: event.proteins,
                    fats: event.fats,
                    carbs: event.carbs
                ),
                items: event.estimateItems,
                context: modelContext
            )
            return
        }
        Task {
            await estimate(event: event, replacingExistingItems: true)
        }
    }

    @MainActor
    private func estimate(event: MealEvent, replacingExistingItems: Bool) async {
        guard let rawText = event.rawText else { return }
        let text = MemoryEngine.normalizeForSync(rawText)
        guard text.count >= 3 else { return }
        event.rawText = text

        let memory = MemoryEngine.resolveSuggestion(for: text, context: modelContext)
        let memoryItems = MemoryEngine.decodeSuggestionItems(memory?.itemsPayload)

        if replacingExistingItems, let memory, !memoryItems.isEmpty, MemoryEngine.normalizeForSync(memory.sourceText).count >= 3 {
            let parsed = memoryItems.map {
                LLMClient.EstimateItemResult(
                    name: $0.name,
                    grams: $0.grams,
                    estimatedCalories: $0.estimatedCalories,
                    estimatedProteins: $0.estimatedProteins,
                    estimatedFats: $0.estimatedFats,
                    estimatedCarbs: $0.estimatedCarbs,
                    impactScore: $0.impactScore,
                    reason: $0.reason,
                    saturatedFats: $0.saturatedFats,
                    sugar: $0.sugar,
                    fiber: $0.fiber,
                    sodium: $0.sodium,
                    foodCategory: $0.foodCategory
                )
            }
            EstimationRuntime.overwriteSnapshot(
                event: event,
                with: parsed,
                mode: EstimateSourceMode.ingredientBreakdown.rawValue,
                modelContext: modelContext
            )
                        let totals = EstimationRuntime.aggregateTotals(items: event.estimateItems)
            event.applyTotals(calories: totals.calories, proteins: totals.proteins, fats: totals.fats, carbs: totals.carbs)
            event.status = .structured
            event.confidence = "medium"
            event.sourceMode = .ingredientBreakdown
            event.modelId = nil
            event.promptVersion = nil
            event.estimationSchemaVersion = nil
            event.structureSource = .memorySuggestion
            event.outOfSync = false
            event.baselineTextNormalized = text
            event.structureLastSyncedAt = Date()
            event.rawPayload = nil
            event.rawPayloadCreatedAt = nil
            event.parseErrorSummary = nil
            event.memoryApplied = true
            try? modelContext.save()
            ruleEngine.generateViolations(for: selectedDate)
            return
        }

        do {
            let result = try await LLMClient.estimateMeal(text: text)

            if replacingExistingItems {
                EstimationRuntime.overwriteSnapshot(
                    event: event,
                    with: result.parsed.items,
                    mode: result.parsed.mode,
                    modelContext: modelContext
                )
            }

            let totals = result.parsed.totals

            event.applyTotals(calories: totals.calories, proteins: totals.proteins, fats: totals.fats, carbs: totals.carbs)
            event.status = .structured
            event.confidence = result.parsed.confidence
            event.sourceMode = result.parsed.mode == "ingredient_breakdown" ? .ingredientBreakdown : .compositeItem
            event.modelId = result.parsed.modelId
            event.promptVersion = result.parsed.promptVersion
            event.estimationSchemaVersion = result.parsed.estimationSchemaVersion
            event.structureSource = .llm
            event.outOfSync = false
            event.baselineTextNormalized = text
            event.structureLastSyncedAt = Date()
            event.rawPayload = result.rawPayload
            event.rawPayloadCreatedAt = Date()
            event.parseErrorSummary = nil
            event.memoryApplied = false
                        if result.parsed.confidence == "low" && lacksPortionSignal(text) {
                MemoryEngine.recordDataGap(
                    title: "Не хватает порции",
                    fingerprint: MemoryEngine.normalize(text),
                    context: modelContext
                )
            }
            MemoryEngine.upsertPrimarySuggestion(
                text: text,
                totals: (
                    calories: totals.calories,
                    proteins: totals.proteins,
                    fats: totals.fats,
                    carbs: totals.carbs
                ),
                items: event.estimateItems,
                context: modelContext
            )
            applyHypothesisSignals(for: text)
            try? modelContext.save()
            ruleEngine.generateViolations(for: selectedDate)
            print("Meal estimate saved: \(event.windowLabel), status=\(event.status.rawValue), kcal=\(event.calories)")
        } catch {
            event.status = .parseFailed
            event.parseErrorSummary = error.localizedDescription
            event.rawPayloadCreatedAt = Date()
            event.structureSource = .llm
            try? modelContext.save()
            print("Meal estimate failed: \(event.windowLabel), error=\(error.localizedDescription)")
        }
    }

    private func createSkippedEvent(windowLabel: String) {
        guard latestEvent(for: windowLabel) == nil else { return }
        let event = MealEvent(
            windowLabel: windowLabel,
            timestamp: preferredTimestampForSelectedDay(),
            status: .skipped
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    private func restoreLastSelectedDate() {
        guard !lastSelectedDayKey.isEmpty else {
            selectedDate = DashboardDateLogic.startOfDay(Date())
            return
        }
        guard let restored = DashboardDateLogic.date(from: lastSelectedDayKey) else {
            selectedDate = DashboardDateLogic.startOfDay(Date())
            return
        }
        if isFutureDate(restored) {
            applySelectedDate(Date())
            return
        }
        applySelectedDate(restored, persist: false)
    }

    private func applySelectedDate(_ date: Date, persist: Bool = true) {
        selectedDate = DashboardDateLogic.startOfDay(date)
        guard persist else { return }
        lastSelectedDayKey = DashboardDateLogic.dayKey(for: selectedDate)
    }

    private func isFutureDate(_ date: Date) -> Bool {
        DashboardDateLogic.isFutureDate(date)
    }

    private func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }

    private func preferredTimestampForSelectedDay() -> Date {
        let start = Calendar.current.startOfDay(for: selectedDate)
        if isSameDay(selectedDate, Date()) {
            return Date()
        }
        return Calendar.current.date(byAdding: .hour, value: 12, to: start) ?? start
    }

    private func latestEvent(for windowLabel: String) -> MealEvent? {
        dayEvents.first(where: { $0.windowLabel == windowLabel })
    }

    private func lacksPortionSignal(_ text: String) -> Bool {
        let normalized = text.lowercased()
        if normalized.range(of: "\\b\\d+\\s?(г|гр|грам|кг|мл|ml|шт|порц)", options: .regularExpression) != nil {
            return false
        }
        return true
    }

    @ViewBuilder
    private func hypothesisPromptCard(_ hypothesis: MemoryHypothesis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Уточнение предпочтения")
                .font(.subheadline.bold())
            Text(hypothesis.title)
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("Да") {
                    MemoryEngine.confirmHypothesis(hypothesis)
                    try? modelContext.save()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button("Нет") {
                    MemoryEngine.rejectHypothesis(hypothesis)
                    try? modelContext.save()
                }
                .buttonStyle(.bordered)

                Button("Спросить позже") {
                    MemoryEngine.snoozeHypothesis(hypothesis)
                    try? modelContext.save()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private func applyHypothesisSignals(for text: String) {
        let normalized = text.lowercased()
        if normalized.contains("без рыбы") || normalized.contains("не ем рыбу") || normalized.contains("без рыб") {
            MemoryEngine.applyHypothesisSignal(
                key: "avoid_fish",
                title: "Похоже, вы избегаете рыбу. Это так?",
                context: modelContext
            )
        }
        if normalized.contains("без молока") || normalized.contains("не ем молочное") || normalized.contains("лактоз") {
            MemoryEngine.applyHypothesisSignal(
                key: "avoid_dairy",
                title: "Похоже, вы ограничиваете молочные продукты. Это так?",
                context: modelContext
            )
        }

        let descriptor = FetchDescriptor<MemoryHypothesis>()
        guard let hypotheses = try? modelContext.fetch(descriptor) else { return }
        for hypothesis in hypotheses where hypothesis.status == .confirmed {
            if hypothesis.key == "avoid_fish" &&
                (normalized.contains("лосось") || normalized.contains("тунец") || normalized.contains("рыба")) {
                MemoryEngine.registerHypothesisConflict(hypothesis)
            }
            if hypothesis.key == "avoid_dairy" &&
                (normalized.contains("молоко") || normalized.contains("сыр") || normalized.contains("йогурт")) {
                MemoryEngine.registerHypothesisConflict(hypothesis)
            }
        }
    }
}

struct MealEventEditorView: View {
    private struct ItemDraft: Identifiable {
        let id: PersistentIdentifier
        let item: EstimateItem
        var grams: String
        var calories: String
        var proteins: String
        var fats: String
        var carbs: String
        var macrosLocked: Bool
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let event: MealEvent
    let violations: [RuleViolation]

    @State private var textDraft = ""
    @State private var isSubmitting = false
    @State private var errorText = ""
    @State private var itemDrafts: [ItemDraft] = []
    @State private var pendingOutOfSyncDecision = false
    @State private var showClearStructureConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Текст") {
                    TextField("Что съели?", text: $textDraft, axis: .vertical)
                        .lineLimit(3...8)
                }

                if event.outOfSync {
                    Section {
                        Text("Текст изменён. Структура может быть неактуальна.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } header: {
                        Text("Синхронизация")
                    }
                }

                if event.status == .structured && EstimationRuntime.lowConfidenceWarningVisible(event.confidence) {
                    Section {
                        Text("Оценка с низкой уверенностью. Можно уточнить текст.")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Не хватает точной порции или контекста. Уточнение граммовки повышает точность.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let adviceText {
                    Section("Совет") {
                        Text(adviceText)
                            .font(.caption)
                    }
                }

                if !errorText.isEmpty {
                    Section {
                        Text(errorText).foregroundColor(.red)
                    }
                }

                Section("Состав блюда") {
                    if itemDrafts.isEmpty {
                        Text("Нет позиций для редактирования. Сначала выполните оценку.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Text("Продукт")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("г").frame(width: 44, alignment: .leading)
                                Text("Ккал").frame(width: 40, alignment: .leading)
                                Text("Б").frame(width: 30, alignment: .leading)
                                Text("Ж").frame(width: 30, alignment: .leading)
                                Text("У").frame(width: 30, alignment: .leading)
                            }
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)

                            ForEach($itemDrafts) { $draft in
                                HStack(spacing: 4) {
                                    Text(draft.item.name)
                                        .font(.subheadline.bold())
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    TextField("0", text: $draft.grams)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 44)
                                        .onChange(of: draft.grams) { _, _ in
                                            unlockDraft(draft.id)
                                            recalculateMacrosIfNeeded(for: draft.id)
                                        }
                                    TextField("ккал", text: $draft.calories)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 40)
                                        .multilineTextAlignment(.leading)
                                        .onChange(of: draft.calories) { _, _ in markDraftLocked(draft.id) }
                                    TextField("Б", text: $draft.proteins)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 30)
                                        .multilineTextAlignment(.leading)
                                        .onChange(of: draft.proteins) { _, _ in markDraftLocked(draft.id) }
                                    TextField("Ж", text: $draft.fats)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 30)
                                        .multilineTextAlignment(.leading)
                                        .onChange(of: draft.fats) { _, _ in markDraftLocked(draft.id) }
                                    TextField("У", text: $draft.carbs)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 30)
                                        .multilineTextAlignment(.leading)
                                        .onChange(of: draft.carbs) { _, _ in markDraftLocked(draft.id) }
                                }
                            }
                        }

                        Button("Очистить состав", role: .destructive) {
                            showClearStructureConfirmation = true
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Section {
                    Button(isSubmitting ? "Отправка..." : "Пересчитать по тексту") {
                        if requiresOutOfSyncDecision {
                            pendingOutOfSyncDecision = true
                        } else {
                            reestimate()
                        }
                    }
                    .disabled(isSubmitting || textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(event.windowLabel)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                textDraft = event.rawText ?? ""
                itemDrafts = event.estimateItems
                    .sorted { $0.estimatedCalories > $1.estimatedCalories }
                    .map { item in
                        ItemDraft(
                            id: item.persistentModelID,
                            item: item,
                            grams: Self.format(item.grams),
                            calories: Self.formatWhole(item.estimatedCalories),
                            proteins: Self.formatWhole(item.estimatedProteins),
                            fats: Self.formatWhole(item.estimatedFats),
                            carbs: Self.formatWhole(item.estimatedCarbs),
                            macrosLocked: item.macrosLocked
                        )
                    }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") {
                        applyManualCorrection()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Текст и структура расходятся", isPresented: $pendingOutOfSyncDecision) {
                Button("Пересчитать по тексту") {
                    reestimate()
                }
                Button("Оставить структуру") {
                    keepStructureAsSourceOfTruth()
                }
                Button("Отмена", role: .cancel) { }
            } message: {
                Text("По умолчанию лучше переоценить. Можно оставить текущую структуру и сохранить текст как заметку.")
            }
            .confirmationDialog("Очистить все позиции структуры?", isPresented: $showClearStructureConfirmation) {
                Button("Очистить", role: .destructive) {
                    clearStructureAndSetPending()
                }
                Button("Отмена", role: .cancel) { }
            }
        }
    }

    private func reestimate() {
        let text = MemoryEngine.normalizeForSync(textDraft)
        guard text.count >= 3 else { return }
        if let baseline = event.baselineTextNormalized, baseline == text {
            return
        }

        isSubmitting = true
        errorText = ""

        let oldTotals = (event.calories, event.proteins, event.fats, event.carbs)
        let oldItems = event.estimateItems

        event.rawText = text
        event.status = .pendingEstimation
        try? modelContext.save()

        Task {
            do {
                let result = try await LLMClient.estimateMeal(text: text)

                await MainActor.run {
                    _ = oldItems
                    EstimationRuntime.overwriteSnapshot(
                        event: event,
                        with: result.parsed.items,
                        mode: result.parsed.mode,
                        modelContext: modelContext
                    )

                    event.applyTotals(
                        calories: result.parsed.totals.calories,
                        proteins: result.parsed.totals.proteins,
                        fats: result.parsed.totals.fats,
                        carbs: result.parsed.totals.carbs
                    )
                    event.status = .structured
                    event.confidence = result.parsed.confidence
                    event.sourceMode = result.parsed.mode == "ingredient_breakdown" ? .ingredientBreakdown : .compositeItem
                    event.modelId = result.parsed.modelId
                    event.promptVersion = result.parsed.promptVersion
                    event.estimationSchemaVersion = result.parsed.estimationSchemaVersion
                    event.structureSource = .llm
                    event.outOfSync = false
                    event.baselineTextNormalized = text
                    event.structureLastSyncedAt = Date()
                    event.rawPayload = result.rawPayload
                    event.rawPayloadCreatedAt = Date()
                    event.parseErrorSummary = nil
                    try? modelContext.save()
                    isSubmitting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    event.status = .parseFailed
                    event.parseErrorSummary = error.localizedDescription
                    event.applyTotals(calories: oldTotals.0, proteins: oldTotals.1, fats: oldTotals.2, carbs: oldTotals.3)
                    event.structureSource = .llm
                    event.outOfSync = true
                    try? modelContext.save()
                    errorText = "Не удалось обновить оценку. Можно сохранить текущее состояние без пересчёта."
                    isSubmitting = false
                }
            }
        }
    }

    private func applyManualCorrection() {
        guard areItemDraftsValid else { return }

        for draft in itemDrafts {
            guard
                let calories = Double(draft.calories),
                let proteins = Double(draft.proteins),
                let fats = Double(draft.fats),
                let carbs = Double(draft.carbs)
            else {
                continue
            }

            draft.item.estimatedCalories = calories
            draft.item.estimatedProteins = proteins
            draft.item.estimatedFats = fats
            draft.item.estimatedCarbs = carbs
            draft.item.grams = Double(draft.grams) ?? draft.item.grams
            draft.item.macrosLocked = draft.macrosLocked

        }

        let totals = EstimationRuntime.aggregateTotals(items: event.estimateItems)

        event.applyTotals(calories: totals.calories, proteins: totals.proteins, fats: totals.fats, carbs: totals.carbs)
        event.memoryApplied = false
        event.structureSource = .manualOverride
                MemoryEngine.upsertPrimarySuggestion(
            text: event.rawText ?? "",
            totals: (
                calories: totals.calories,
                proteins: totals.proteins,
                fats: totals.fats,
                carbs: totals.carbs
            ),
            items: event.estimateItems,
            context: modelContext
        )
        try? modelContext.save()
    }

    private var areItemDraftsValid: Bool {
        !itemDrafts.isEmpty && itemDrafts.allSatisfy {
            Double($0.grams) != nil &&
            Double($0.calories) != nil &&
            Double($0.proteins) != nil &&
            Double($0.fats) != nil &&
            Double($0.carbs) != nil
        }
    }

    private var requiresOutOfSyncDecision: Bool {
        MemoryPresentation.shouldPromptOutOfSync(
            source: event.structureSource,
            selectedText: event.baselineTextNormalized,
            currentText: textDraft
        )
    }

    private func keepStructureAsSourceOfTruth() {
        event.userNote = MemoryEngine.normalizeForSync(textDraft)
        event.outOfSync = MemoryEngine.isOutOfSync(selectedText: event.baselineTextNormalized, currentText: textDraft)
        try? modelContext.save()
        dismiss()
    }

    private var adviceText: String? {
        let reasons = event.estimateItems
            .map(\.reason)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let merged = reasons.prefix(2).joined(separator: " ")
        guard let cleaned = MemoryPresentation.cleanAdviceText(merged) else { return nil }
        if event.structureSource == .memorySuggestion && !MemoryPresentation.isAdviceUseful(cleaned) {
            return nil
        }
        return cleaned
    }

    private func markDraftLocked(_ id: PersistentIdentifier) {
        guard let index = itemDrafts.firstIndex(where: { $0.id == id }) else { return }
        itemDrafts[index].macrosLocked = true
    }

    private func recalculateMacrosIfNeeded(for id: PersistentIdentifier) {
        guard let index = itemDrafts.firstIndex(where: { $0.id == id }) else { return }
        guard let grams = Double(itemDrafts[index].grams), grams > 0 else { return }
        let base = itemDrafts[index].item
        let baseline = max(0.1, base.baseGrams)
        let scale = grams / baseline
        itemDrafts[index].calories = Self.formatWhole(base.baseCalories * scale)
        itemDrafts[index].proteins = Self.formatWhole(base.baseProteins * scale)
        itemDrafts[index].fats = Self.formatWhole(base.baseFats * scale)
        itemDrafts[index].carbs = Self.formatWhole(base.baseCarbs * scale)
    }

    private func unlockDraft(_ id: PersistentIdentifier) {
        guard let index = itemDrafts.firstIndex(where: { $0.id == id }) else { return }
        itemDrafts[index].macrosLocked = false
    }

    private func clearStructureAndSetPending() {
        let oldItems = Array(event.estimateItems)
        itemDrafts = []
        event.applyTotals(calories: 0, proteins: 0, fats: 0, carbs: 0)
        event.status = .pendingEstimation
        event.parseErrorSummary = nil
        event.outOfSync = true
        event.structureLastSyncedAt = nil
        for oldItem in oldItems {
            modelContext.delete(oldItem)
        }
        try? modelContext.save()
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private static func formatWhole(_ value: Double) -> String {
        String(Int(value.rounded()))
    }

}

struct LogSheetView: View {
    private enum SaveMode {
        case reestimateFromText
        case keepDraftStructure
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let windowLabel: String
    let initialText: String
    let onSave: (DashboardView.LogDraftResult) -> Void

    @State private var logText: String
    @State private var selectedSuggestion: MemoryEngine.SuggestionViewModel?
    @State private var saveMode: SaveMode = .reestimateFromText
    @State private var showOutOfSyncDecision = false
    @State private var suggestions: [MemoryEngine.SuggestionViewModel] = []
    @State private var selectedPortionGrams: Int?
    @State private var customPortionGrams = ""

    init(windowLabel: String, initialText: String, onSave: @escaping (DashboardView.LogDraftResult) -> Void) {
        self.windowLabel = windowLabel
        self.initialText = initialText
        self.onSave = onSave
        _logText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Что съели?", text: $logText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4...8)
                    .onChange(of: logText) { _, newValue in
                        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            selectedSuggestion = nil
                            saveMode = .reestimateFromText
                            suggestions = []
                            return
                        }
                        refreshSuggestions()
                    }

                if !suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.canonicalKey) { suggestion in
                                Button(suggestion.text) {
                                    selectedSuggestion = suggestion
                                    logText = suggestion.text
                                    saveMode = .reestimateFromText
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                if let selectedSuggestion {
                    HStack(spacing: 6) {
                        Text("Из памяти")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                        Text("\(Int(selectedSuggestion.calories)) ккал")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Уточнить порцию")
                            .font(.caption.bold())
                        HStack {
                            ForEach([200, 300, 500], id: \.self) { grams in
                                Button("\(grams)г") {
                                    selectedPortionGrams = grams
                                }
                                .buttonStyle(.bordered)
                                .tint(selectedPortionGrams == grams ? .blue : .gray)
                            }
                            TextField("Свой", text: $customPortionGrams)
                                .keyboardType(.numberPad)
                                .frame(width: 70)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: customPortionGrams) { _, value in
                                    if let grams = Int(value), grams > 0 {
                                        selectedPortionGrams = grams
                                    }
                                }
                            Text("г")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button("Готово") {
                    handleSaveTap()
                }
                .disabled(logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .frame(maxWidth: .infinity)
                .padding()
                .background(logText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)

                Spacer()
            }
            .padding()
            .navigationTitle(windowLabel)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                refreshSuggestions()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .confirmationDialog("Текст отличается от структуры", isPresented: $showOutOfSyncDecision) {
                Button("Переоценить по тексту") {
                    saveMode = .reestimateFromText
                    completeSave()
                }
                Button("Оставить структуру") {
                    saveMode = .keepDraftStructure
                    completeSave()
                }
                Button("Отмена", role: .cancel) { }
            } message: {
                Text("Если оставить структуру, текст сохранится как заметка и не повлияет на расчёт.")
            }
        }
    }

    private func handleSaveTap() {
        guard let selectedSuggestion else {
            completeSave()
            return
        }
        if MemoryEngine.isOutOfSync(selectedText: selectedSuggestion.text, currentText: logText) {
            showOutOfSyncDecision = true
            return
        }
        saveMode = .keepDraftStructure
        completeSave()
    }

    private func completeSave() {
        let trimmed = MemoryEngine.normalizeForSync(logText)
        guard trimmed.count >= 3 else { return }

        let draftStructure: DashboardView.ManualDraftStructure?
        if let selectedSuggestion {
            let adjusted = adjustedByPortion(base: selectedSuggestion)
            let portionScale = selectedPortionScale(base: selectedSuggestion)
            draftStructure = DashboardView.ManualDraftStructure(
                calories: adjusted.calories,
                proteins: adjusted.proteins,
                fats: adjusted.fats,
                carbs: adjusted.carbs,
                source: .memorySuggestion,
                sourceText: selectedSuggestion.text,
                items: selectedSuggestion.items.map {
                    DashboardView.ManualDraftStructure.DraftItem(
                        name: $0.name,
                        grams: max(1, $0.grams * portionScale),
                        calories: max(0, $0.estimatedCalories * portionScale),
                        proteins: max(0, $0.estimatedProteins * portionScale),
                        fats: max(0, $0.estimatedFats * portionScale),
                        carbs: max(0, $0.estimatedCarbs * portionScale),
                        impactScore: $0.impactScore,
                        reason: $0.reason
                    )
                }
            )
            MemoryEngine.confirmDataGap(
                fingerprint: selectedSuggestion.canonicalKey,
                context: modelContext
            )
        } else {
            draftStructure = nil
        }

        onSave(
            DashboardView.LogDraftResult(
                text: trimmed,
                draftStructure: draftStructure,
                treatTextAsNote: saveMode == .keepDraftStructure,
                keepStructureWithoutReestimate: saveMode == .keepDraftStructure
            )
        )
        dismiss()
    }

    private func refreshSuggestions() {
        let trimmed = logText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions = []
            return
        }

        let eventDescriptor = FetchDescriptor<MealEvent>(
            sortBy: [SortDescriptor(\MealEvent.timestamp, order: .reverse)]
        )
        let events = (try? modelContext.fetch(eventDescriptor)) ?? []

        let suggestionDescriptor = FetchDescriptor<MemorySuggestion>(
            sortBy: [SortDescriptor(\MemorySuggestion.lastUsedAt, order: .reverse)]
        )
        let stored = (try? modelContext.fetch(suggestionDescriptor)) ?? []

        suggestions = MemoryEngine.topSuggestions(
            query: trimmed,
            from: events,
            suggestions: stored,
            limit: 5
        )
    }

    private func adjustedByPortion(base: MemoryEngine.SuggestionViewModel) -> (calories: Double, proteins: Double, fats: Double, carbs: Double) {
        let scale = selectedPortionScale(base: base)
        guard scale != 1 else {
            return (base.calories, base.proteins, base.fats, base.carbs)
        }
        return (
            max(0, base.calories * scale),
            max(0, base.proteins * scale),
            max(0, base.fats * scale),
            max(0, base.carbs * scale)
        )
    }

    private func selectedPortionScale(base: MemoryEngine.SuggestionViewModel) -> Double {
        guard let grams = selectedPortionGrams else { return 1 }
        let baseGrams = max(1.0, base.items.reduce(0) { $0 + $1.grams })
        return Double(grams) / baseGrams
    }
}

private struct DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftDate: Date
    let onSelect: (Date) -> Void

    init(selectedDate: Date, onSelect: @escaping (Date) -> Void) {
        _draftDate = State(initialValue: selectedDate)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker(
                    "Дата",
                    selection: $draftDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)

                Button("Выбрать") {
                    onSelect(draftDate)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
            .navigationTitle("Выбор даты")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}
