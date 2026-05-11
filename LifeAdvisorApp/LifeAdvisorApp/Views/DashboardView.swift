import SwiftUI
import SwiftData

struct DashboardView: View {
    struct ManualDraftStructure {
        var calories: Double
        var proteins: Double
        var fats: Double
        var carbs: Double
        var source: StructureSource
    }

    struct LogDraftResult {
        var text: String
        var draftStructure: ManualDraftStructure?
        var treatTextAsNote: Bool
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealWindow.order) private var windows: [MealWindow]
    @StateObject private var notificationManager = NotificationManager.shared
    @AppStorage("dashboard_last_selected_day") private var lastSelectedDayKey = ""

    @State private var selectedWindow: String?
    @State private var editingEvent: MealEvent?
    @State private var logText = ""
    @State private var selectedDate = DashboardDateLogic.startOfDay(Date())
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

                    Button {
                        requestDailyAdvice()
                    } label: {
                        Text("Совет дня")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canGetAdvice ? Color.green : Color.gray.opacity(0.3))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .disabled(!canGetAdvice)
                }
                .padding(.vertical)
            }
            .navigationTitle("Дашборд")
            .onAppear {
                restoreLastSelectedDate()
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
                MealEventEditorView(event: event)
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

    private var canGetAdvice: Bool {
        let labels = windows.map(\.name)
        guard !labels.isEmpty else { return false }
        return labels.allSatisfy { label in
            guard let event = latestEvent(for: label) else { return false }
            return event.status == .structured || event.status == .skipped
        }
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
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        clearRecommendationCacheForToday()

        let event: MealEvent
        if let existing = latestEvent(for: windowLabel) {
            event = existing
            event.rawText = text
            event.userNote = draft.treatTextAsNote ? text : nil
            event.status = .pendingEstimation
            event.structureSource = .llm
            event.outOfSync = false
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
            modelContext.insert(created)
            event = created
            print("Meal upsert: create new event for \(windowLabel), id=\(created.persistentModelID)")
        }

        if let draftStructure = draft.draftStructure, draft.treatTextAsNote {
            event.applyTotals(
                calories: draftStructure.calories,
                proteins: draftStructure.proteins,
                fats: draftStructure.fats,
                carbs: draftStructure.carbs
            )
            event.status = .structured
            event.structureSource = draftStructure.source
            event.outOfSync = true
            event.confidence = "medium"
            event.memoryApplied = draftStructure.source == .memorySuggestion
            let sourceMode: EstimateSourceMode = .compositeItem
            EstimationRuntime.overwriteSnapshot(
                event: event,
                with: [
                    LLMClient.EstimateItemResult(
                        name: text,
                        grams: 100,
                        estimatedCalories: draftStructure.calories,
                        estimatedProteins: draftStructure.proteins,
                        estimatedFats: draftStructure.fats,
                        estimatedCarbs: draftStructure.carbs,
                        impactScore: 1,
                        reason: "Из памяти",
                        highCalorieFlag: draftStructure.calories >= 450
                    )
                ],
                mode: sourceMode.rawValue,
                modelContext: modelContext
            )
        }
        try? modelContext.save()

        if draft.draftStructure != nil && draft.treatTextAsNote {
            return
        }
        Task {
            await estimate(event: event, replacingExistingItems: true)
        }
    }

    @MainActor
    private func estimate(event: MealEvent, replacingExistingItems: Bool) async {
        guard let text = event.rawText, !text.isEmpty else { return }

        let memory = MemoryEngine.resolveSuggestion(for: text, context: modelContext)

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

            let totals = EstimationRuntime.applySuggestionPrior(totals: result.parsed.totals, suggestion: memory)

            event.applyTotals(calories: totals.calories, proteins: totals.proteins, fats: totals.fats, carbs: totals.carbs)
            event.status = .structured
            event.confidence = result.parsed.confidence
            event.sourceMode = result.parsed.mode == "ingredient_breakdown" ? .ingredientBreakdown : .compositeItem
            event.modelId = result.parsed.modelId
            event.promptVersion = result.parsed.promptVersion
            event.estimationSchemaVersion = result.parsed.estimationSchemaVersion
            event.structureSource = .llm
            event.outOfSync = false
            event.rawPayload = result.rawPayload
            event.rawPayloadCreatedAt = Date()
            event.parseErrorSummary = nil
            event.memoryApplied = memory != nil
            if result.parsed.confidence == "low" && lacksPortionSignal(text) {
                MemoryEngine.recordDataGap(
                    title: "Не хватает порции",
                    fingerprint: MemoryEngine.normalize(text),
                    context: modelContext
                )
            }
            MemoryEngine.upsertPrimarySuggestion(
                text: text,
                totals: totals,
                context: modelContext
            )
            applyHypothesisSignals(for: text)
            try? modelContext.save()
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
        clearRecommendationCacheForToday()

        let event = MealEvent(
            windowLabel: windowLabel,
            timestamp: preferredTimestampForSelectedDay(),
            status: .skipped
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    private func clearRecommendationCacheForToday() {
        let key = DailyAdvice.dateKey(from: Date())
        let descriptor = FetchDescriptor<Recommendation>(predicate: #Predicate { $0.date == key })
        if let rec = try? modelContext.fetch(descriptor).first {
            modelContext.delete(rec)
            try? modelContext.save()
        }
    }

    private func requestDailyAdvice() {
        let goalCalories = UserDefaults.standard.double(forKey: "goal_calories")
        let labels = windows.map(\.name)
        let events = dayEvents.filter { labels.contains($0.windowLabel) }

        let meals = events
            .filter { $0.status == .structured }
            .map { ($0.windowLabel, $0.calories, $0.proteins, $0.fats, $0.carbs) }

        let skipped = events.filter { $0.status == .skipped }.map(\.windowLabel)

        Task {
            do {
                let advice = try await LLMClient.dailyAdvice(meals: meals, goalCalories: goalCalories, skippedWindows: skipped)
                let dateKey = DailyAdvice.dateKey(from: Date())
                let descriptor = FetchDescriptor<DailyAdvice>(predicate: #Predicate { $0.date == dateKey })
                if let existing = try? modelContext.fetch(descriptor).first {
                    existing.adviceText = advice
                    existing.createdAt = Date()
                } else {
                    modelContext.insert(DailyAdvice(date: dateKey, adviceText: advice))
                }
                try? modelContext.save()
            } catch {
                print("Daily advice error: \(error)")
            }
        }
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

struct MealSlotCard: View {
    let windowLabel: String
    let timeRange: String
    let event: MealEvent?
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(windowLabel).font(.headline)
                Spacer()
                Text(timeRange).font(.caption).foregroundColor(.secondary)
            }

            if let event {
                switch event.status {
                case .skipped:
                    Label("Пропущено", systemImage: "slash.circle")
                        .foregroundColor(.secondary)
                case .pendingEstimation:
                    Label(event.rawText ?? "Оценка...", systemImage: "clock")
                        .foregroundColor(.orange)
                case .parseFailed:
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.rawText ?? "")
                        Text("Последняя оценка не обновлена")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                case .structured:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(event.calories)) ккал").font(.title3.bold())
                        Text("Б: \(Int(event.proteins))г Ж: \(Int(event.fats))г У: \(Int(event.carbs))г")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(event.estimateItems.prefix(3), id: \.persistentModelID) { item in
                            HStack {
                                Text(item.name).font(.caption)
                                Spacer()
                                Text("\(Int(item.estimatedCalories)) ккал").font(.caption2)
                            }
                            .foregroundColor(item.highCalorieFlag ? .red : .secondary)
                        }
                    }
                case .empty:
                    EmptyView()
                }
            } else {
                Label("Записать приём пищи", systemImage: "plus.circle")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var backgroundColor: Color {
        guard let event else { return Color.gray.opacity(0.15) }
        switch event.status {
        case .empty: return Color.gray.opacity(0.15)
        case .pendingEstimation: return Color.yellow.opacity(0.2)
        case .structured: return Color.green.opacity(0.2)
        case .parseFailed: return Color.orange.opacity(0.2)
        case .skipped: return Color.gray.opacity(0.15)
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
                        Text("Изменения сохраняются автоматически")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Text("г").frame(width: 60, alignment: .leading)
                                Text("Ккал").frame(width: 44, alignment: .leading)
                                Text("Б").frame(width: 44, alignment: .leading)
                                Text("Ж").frame(width: 44, alignment: .leading)
                                Text("У").frame(width: 44, alignment: .leading)
                            }
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)

                            ForEach($itemDrafts) { $draft in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(draft.item.name).font(.subheadline.bold())
                                    HStack(spacing: 4) {
                                        TextField("0", text: $draft.grams)
                                            .keyboardType(.decimalPad)
                                            .frame(width: 60)
                                            .onChange(of: draft.grams) { _, _ in
                                                unlockDraft(draft.id)
                                                recalculateMacrosIfNeeded(for: draft.id)
                                            }
                                        TextField("ккал", text: $draft.calories)
                                            .keyboardType(.decimalPad)
                                            .frame(width: 44)
                                            .multilineTextAlignment(.leading)
                                            .onChange(of: draft.calories) { _, _ in markDraftLocked(draft.id) }
                                        TextField("Б", text: $draft.proteins)
                                            .keyboardType(.decimalPad)
                                            .frame(width: 44)
                                            .multilineTextAlignment(.leading)
                                            .onChange(of: draft.proteins) { _, _ in markDraftLocked(draft.id) }
                                        TextField("Ж", text: $draft.fats)
                                            .keyboardType(.decimalPad)
                                            .frame(width: 44)
                                            .multilineTextAlignment(.leading)
                                            .onChange(of: draft.fats) { _, _ in markDraftLocked(draft.id) }
                                        TextField("У", text: $draft.carbs)
                                            .keyboardType(.decimalPad)
                                            .frame(width: 44)
                                            .multilineTextAlignment(.leading)
                                            .onChange(of: draft.carbs) { _, _ in markDraftLocked(draft.id) }
                                    }
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
                            calories: Self.format(item.estimatedCalories),
                            proteins: Self.format(item.estimatedProteins),
                            fats: Self.format(item.estimatedFats),
                            carbs: Self.format(item.estimatedCarbs),
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
        let text = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

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
                    try? modelContext.save()
                    errorText = "Не удалось обновить оценку. Исправьте текст и попробуйте снова."
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
        event.outOfSync = false
        MemoryEngine.upsertPrimarySuggestion(
            text: event.rawText ?? "",
            totals: (
                calories: totals.calories,
                proteins: totals.proteins,
                fats: totals.fats,
                carbs: totals.carbs
            ),
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
            selectedText: event.rawText,
            currentText: textDraft
        )
    }

    private func keepStructureAsSourceOfTruth() {
        event.userNote = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        event.outOfSync = true
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
        itemDrafts[index].calories = Self.format(base.baseCalories * scale)
        itemDrafts[index].proteins = Self.format(base.baseProteins * scale)
        itemDrafts[index].fats = Self.format(base.baseFats * scale)
        itemDrafts[index].carbs = Self.format(base.baseCarbs * scale)
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
        let trimmed = logText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let draftStructure: DashboardView.ManualDraftStructure?
        if let selectedSuggestion {
            let adjusted = adjustedByPortion(base: selectedSuggestion)
            draftStructure = DashboardView.ManualDraftStructure(
                calories: adjusted.calories,
                proteins: adjusted.proteins,
                fats: adjusted.fats,
                carbs: adjusted.carbs,
                source: .memorySuggestion
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
                treatTextAsNote: saveMode == .keepDraftStructure
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
        guard let grams = selectedPortionGrams else {
            return (base.calories, base.proteins, base.fats, base.carbs)
        }
        let scale = Double(grams) / 300.0
        return (
            max(0, base.calories * scale),
            max(0, base.proteins * scale),
            max(0, base.fats * scale),
            max(0, base.carbs * scale)
        )
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
