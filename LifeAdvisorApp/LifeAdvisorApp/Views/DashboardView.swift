import SwiftUI
import SwiftData

struct DashboardView: View {
    @Binding var selectedDate: Date
    @StateObject private var languageManager = AppLanguageManager.shared
    @EnvironmentObject private var agentSession: AgentSessionStore

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

    @State private var showDatePicker = false
    @State private var showFutureDateHint = false
    @State private var showCancelExecutionAlert = false
    @State private var commitFeedback: String?

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
                            let event = latestEvent(for: window.windowId)
                            MealSlotCard(
                                windowLabel: window.localizedName(language: languageManager.effectiveLanguage),
                                timeRange: "\(window.startTimeString)–\(window.endTimeString)",
                                event: event,
                                engine: ruleEngine,
                                onTap: {
                                },
                                executionContext: executionContext(for: window)
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
            .onChange(of: agentSession.mealSession?.activeStep?.day) { _, value in
                guard let value else { return }
                applySelectedDate(value)
            }
            .onChange(of: notificationManager.pendingLogWindow) { _, value in
                guard value != nil else { return }
                notificationManager.pendingLogWindow = nil
            }
            .onChange(of: notificationManager.pendingSkipWindow) { _, value in
                guard let value else { return }
                createSkippedEvent(windowLabel: value)
                notificationManager.pendingSkipWindow = nil
            }
            .sheet(isPresented: chatSheetBinding) {
                AgentChatInputSheet(isPlanning: agentSession.phase == .planning) { message in
                    Task {
                        await startAgentPlanning(message: message)
                    }
                }
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
            .alert("Несохранённые шаги будут потеряны", isPresented: $showCancelExecutionAlert) {
                Button("Отменить flow", role: .destructive) {
                    agentSession.cancel()
                    agentSession.resetToIdle()
                }
                Button("Продолжить", role: .cancel) { }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let commitFeedback {
                        Text(commitFeedback)
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.14), in: Capsule())
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if let session = agentSession.mealSession, agentSession.phase == .executing {
                        MealExecutionBottomBar(session: session) {
                            showCancelExecutionAlert = true
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: commitFeedback)
            }
        }
    }

    private var chatSheetBinding: Binding<Bool> {
        .init(
            get: { agentSession.isChatPresented && agentSession.activeDomain == .meal },
            set: { isPresented in
                agentSession.handleChatPresentationChange(isPresented: isPresented)
            }
        )
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

    private func planningContext(for message: String) -> MealPlanningContext {
        _ = message
        return MealPlanningContext(selectedDate: selectedDate, dayEvents: dayEvents, windows: windows)
    }

    @MainActor
    private func startAgentPlanning(message: String) async {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 3 else { return }
        agentSession.beginPlanning()
        let route = AgentScenarioRouter.route(message: normalized)
        guard route == .meal else {
            agentSession.resetToIdle()
            return
        }

        let context = planningContext(for: normalized)
        let classification = await MealScenarioClassifier.classify(normalized, context: context)
        do {
            let session = try await MealStepPlanner.plan(
                message: normalized,
                classification: classification,
                context: context
            )
            applySelectedDate(session.activeStep?.day ?? selectedDate)
            agentSession.startMealExecution(session)
        } catch {
            agentSession.resetToIdle()
        }
    }

    private func executionContext(for window: MealWindow) -> MealSlotExecutionContext? {
        guard
            agentSession.phase == .executing,
            let session = agentSession.mealSession,
            let activeStep = session.activeStep,
            DashboardDateLogic.startOfDay(activeStep.day) == DashboardDateLogic.startOfDay(selectedDate),
            activeStep.windowId == window.windowId
        else {
            return nil
        }

        return MealSlotExecutionContext(
            stepType: activeStep.type,
            products: activeStep.products,
            selectedDayLabel: activeStep.day.formatted(.dateTime.day().month(.abbreviated)),
            selectedSlotLabel: windows.first(where: { $0.windowId == activeStep.windowId })?.localizedName(language: languageManager.effectiveLanguage) ?? activeStep.windowId,
            resolveKind: activeStep.resolveKind,
            onNameChange: { id, value in
                agentSession.updateMealSession { session in
                    guard session.steps.indices.contains(session.activeStepIndex) else { return }
                    guard let productIndex = session.steps[session.activeStepIndex].products.firstIndex(where: { $0.id == id }) else { return }
                    session.steps[session.activeStepIndex].products[productIndex].name = value
                }
            },
            onGramsChange: { id, value in
                guard let grams = Double(value) else { return }
                agentSession.updateMealSession { session in
                    guard session.steps.indices.contains(session.activeStepIndex) else { return }
                    guard let productIndex = session.steps[session.activeStepIndex].products.firstIndex(where: { $0.id == id }) else { return }
                    session.steps[session.activeStepIndex].products[productIndex].updateGrams(grams)
                }
            },
            onRemove: { id in
                agentSession.updateMealSession { session in
                    guard session.steps.indices.contains(session.activeStepIndex) else { return }
                    session.steps[session.activeStepIndex].products.removeAll { $0.id == id }
                }
            },
            onAdd: {
                agentSession.updateMealSession { session in
                    guard session.steps.indices.contains(session.activeStepIndex) else { return }
                    session.steps[session.activeStepIndex].products.append(
                        MealProductDraft(
                            name: "",
                            grams: 100,
                            estimatedCalories: 120,
                            estimatedProteins: 5,
                            estimatedFats: 4,
                            estimatedCarbs: 15,
                            reason: "Добавлено вручную"
                        )
                    )
                }
            },
            onConfirm: {
                confirmActiveExecutionStep()
            },
            onResolveToEdit: {
                agentSession.updateMealSession { session in
                    guard session.steps.indices.contains(session.activeStepIndex) else { return }
                    session.steps[session.activeStepIndex].type = .edit
                    MealResolveEngine.applyResolveState(
                        to: &session.steps[session.activeStepIndex],
                        existingEvent: latestEvent(
                            for: session.steps[session.activeStepIndex].windowId,
                            on: session.steps[session.activeStepIndex].day
                        )
                    )
                }
            },
            onResolveToDayOffset: { offset in
                applyResolveDayOffset(offset)
            },
            onResolveToWindow: { windowId in
                applyResolveWindow(windowId)
            }
        )
    }

    private func applyResolveDayOffset(_ offset: Int) {
        let baseDay = agentSession.mealSession?.activeStep?.day ?? selectedDate
        let targetDay = Calendar.current.date(byAdding: .day, value: offset, to: baseDay) ?? baseDay
        updateActiveStepResolution(day: targetDay, windowId: nil)
    }

    private func applyResolveWindow(_ windowId: String) {
        updateActiveStepResolution(day: nil, windowId: windowId)
    }

    private func updateActiveStepResolution(day: Date?, windowId: String?) {
        let updatedDay = day.map { DashboardDateLogic.startOfDay($0) }
        agentSession.updateMealSession { session in
            guard session.steps.indices.contains(session.activeStepIndex) else { return }
            if let updatedDay {
                session.steps[session.activeStepIndex].day = updatedDay
            }
            if let windowId {
                session.steps[session.activeStepIndex].windowId = windowId
                session.steps[session.activeStepIndex].title = windows.first(where: { $0.windowId == windowId })?.localizedName() ?? windowId
            }
            let currentStep = session.steps[session.activeStepIndex]
            let existingEvent = latestEvent(for: currentStep.windowId, on: currentStep.day)
            MealResolveEngine.applyResolveState(
                to: &session.steps[session.activeStepIndex],
                existingEvent: existingEvent
            )
        }
        if let currentDay = agentSession.mealSession?.activeStep?.day {
            applySelectedDate(currentDay)
        }
    }

    private func confirmActiveExecutionStep() {
        guard let session = agentSession.mealSession, let step = session.activeStep else { return }
        let draftProducts = step.products.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !draftProducts.isEmpty else { return }

        let currentResolve = MealResolveEngine.resolveKind(
            for: step,
            existingEvent: latestEvent(for: step.windowId, on: step.day)
        )
        if let currentResolve {
            agentSession.updateMealSession { session in
                guard session.steps.indices.contains(session.activeStepIndex) else { return }
                session.steps[session.activeStepIndex].state = .needsResolve
                session.steps[session.activeStepIndex].resolveKind = currentResolve
            }
            return
        }

        let targetEvent: MealEvent
        if step.type == .edit, let existing = latestEvent(for: step.windowId, on: step.day) {
            targetEvent = existing
        } else {
            let created = MealEvent(
                windowLabel: step.windowId,
                timestamp: preferredTimestamp(for: step.windowId, on: step.day),
                status: .structured,
                rawText: step.sourceText
            )
            created.structureSource = .llm
            modelContext.insert(created)
            targetEvent = created
        }

        targetEvent.rawText = step.sourceText
        targetEvent.status = .structured
        targetEvent.structureSource = .llm
        targetEvent.outOfSync = false
        targetEvent.baselineTextNormalized = MemoryEngine.normalizeForSync(step.sourceText)
        targetEvent.structureLastSyncedAt = Date()
        targetEvent.parseErrorSummary = nil
        targetEvent.memoryApplied = false
        targetEvent.confidence = "medium"
        targetEvent.sourceMode = .ingredientBreakdown

        EstimationRuntime.overwriteSnapshot(
            event: targetEvent,
            with: draftProducts.map {
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
            },
            mode: EstimateSourceMode.ingredientBreakdown.rawValue,
            modelContext: modelContext
        )
        let totals = EstimationRuntime.aggregateTotals(items: targetEvent.estimateItems)
        targetEvent.applyTotals(calories: totals.calories, proteins: totals.proteins, fats: totals.fats, carbs: totals.carbs)
        try? modelContext.save()
        ruleEngine.resetWeekIfNeeded()
        ruleEngine.generateViolations(for: step.day)
        showCommitFeedback(for: step)

        var shouldFinishSession = false
        agentSession.updateMealSession { session in
            guard session.steps.indices.contains(session.activeStepIndex) else { return }
            session.steps[session.activeStepIndex].state = .committed
            if session.activeStepIndex < session.steps.count - 1 {
                session.activeStepIndex += 1
            } else {
                shouldFinishSession = true
            }
        }
        if shouldFinishSession {
            agentSession.markCompleted()
            agentSession.resetToIdle()
        }
    }

    private func showCommitFeedback(for step: MealExecutionStep) {
        let slotName = windows.first(where: { $0.windowId == step.windowId })?.localizedName(language: languageManager.effectiveLanguage) ?? step.title
        commitFeedback = step.type == .create ? "\(slotName) сохранен" : "\(slotName) обновлен"
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            if commitFeedback != nil {
                commitFeedback = nil
            }
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

    private func preferredTimestamp(for windowId: String, on day: Date) -> Date {
        let start = Calendar.current.startOfDay(for: day)
        guard let window = windows.first(where: { $0.windowId == windowId }) else {
            return Calendar.current.date(byAdding: .hour, value: 12, to: start) ?? start
        }
        return Calendar.current.date(byAdding: .hour, value: window.startHour + 1, to: start) ?? start
    }

    private func latestEvent(for windowLabel: String) -> MealEvent? {
        dayEvents.first(where: { $0.windowLabel == windowLabel })
    }

    private func latestEvent(for windowLabel: String, on day: Date) -> MealEvent? {
        let range = DashboardDateLogic.dayRange(for: day)
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<MealEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\MealEvent.timestamp, order: .reverse)]
        )
        let events = (try? modelContext.fetch(descriptor)) ?? []
        return events.first(where: { $0.windowLabel == windowLabel })
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
    private enum EditorDialog: String, Identifiable {
        case outOfSyncDecision
        case clearStructure

        var id: String { rawValue }
    }

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
    @StateObject private var languageManager = AppLanguageManager.shared
    @State private var ruleEngine = RuleEngine()

    let event: MealEvent
    let violations: [RuleViolation]

    @State private var textDraft = ""
    @State private var isSubmitting = false
    @State private var errorText = ""
    @State private var itemDrafts: [ItemDraft] = []
    @State private var activeDialog: EditorDialog?
    @FocusState private var editorFieldFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Текст") {
                    TextField("Что съели?", text: $textDraft, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($editorFieldFocused)
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
                                Text(LocalizationHelper.localized("Ккал", table: "Localizable", language: languageManager.effectiveLanguage)).frame(width: 40, alignment: .leading)
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
                                        .focused($editorFieldFocused)
                                        .onChange(of: draft.grams) { _, _ in
                                            unlockDraft(draft.id)
                                            recalculateMacrosIfNeeded(for: draft.id)
                                        }
                                    TextField(LocalizationHelper.localized("ккал", table: "Localizable", language: languageManager.effectiveLanguage), text: $draft.calories)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 40)
                                        .multilineTextAlignment(.leading)
                                        .focused($editorFieldFocused)
                                        .onChange(of: draft.calories) { _, _ in markDraftLocked(draft.id) }
                                    TextField("Б", text: $draft.proteins)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 30)
                                        .multilineTextAlignment(.leading)
                                        .focused($editorFieldFocused)
                                        .onChange(of: draft.proteins) { _, _ in markDraftLocked(draft.id) }
                                    TextField("Ж", text: $draft.fats)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 30)
                                        .multilineTextAlignment(.leading)
                                        .focused($editorFieldFocused)
                                        .onChange(of: draft.fats) { _, _ in markDraftLocked(draft.id) }
                                    TextField("У", text: $draft.carbs)
                                        .keyboardType(.decimalPad)
                                        .frame(width: 30)
                                        .multilineTextAlignment(.leading)
                                        .focused($editorFieldFocused)
                                        .onChange(of: draft.carbs) { _, _ in markDraftLocked(draft.id) }
                                }
                            }
                        }

                        Button(role: .destructive) {
                            editorFieldFocused = false
                            activeDialog = .clearStructure
                        } label: {
                            Text("Очистить состав")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                Section {
                    Button {
                        editorFieldFocused = false
                        if requiresOutOfSyncDecision {
                            activeDialog = .outOfSyncDecision
                        } else {
                            reestimate()
                        }
                    } label: {
                        Text(isSubmitting ? "Отправка..." : "Пересчитать по тексту")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isSubmitting || textDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(event.windowLabel)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                ruleEngine.configure(context: modelContext)
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
            .confirmationDialog(
                activeDialog == .outOfSyncDecision
                    ? "Текст и структура расходятся"
                    : "Очистить все позиции структуры?",
                isPresented: Binding(
                    get: { activeDialog != nil },
                    set: { if !$0 { activeDialog = nil } }
                ),
                titleVisibility: .visible
            ) {
                switch activeDialog {
                case .outOfSyncDecision:
                    Button("Пересчитать по тексту") {
                        activeDialog = nil
                        reestimate()
                    }
                    Button("Оставить структуру") {
                        activeDialog = nil
                        keepStructureAsSourceOfTruth()
                    }
                    Button("Отмена", role: .cancel) {
                        activeDialog = nil
                    }
                case .clearStructure:
                    Button("Очистить", role: .destructive) {
                        activeDialog = nil
                        clearStructureAndSetPending()
                    }
                    Button("Отмена", role: .cancel) {
                        activeDialog = nil
                    }
                case .none:
                    EmptyView()
                }
            } message: {
                switch activeDialog {
                case .outOfSyncDecision:
                    Text("По умолчанию лучше переоценить. Можно оставить текущую структуру и сохранить текст как заметку.")
                case .clearStructure:
                    EmptyView()
                case .none:
                    EmptyView()
                }
            }
        }
    }

    private func reestimate() {
        let text = MemoryEngine.normalizeForSync(textDraft)
        guard text.count >= 3 else { return }

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
                    ruleEngine.resetWeekIfNeeded()
                    ruleEngine.generateViolations(for: event.timestamp)
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
        ruleEngine.resetWeekIfNeeded()
        ruleEngine.generateViolations(for: event.timestamp)
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
        ruleEngine.resetWeekIfNeeded()
        ruleEngine.generateViolations(for: event.timestamp)
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
        ruleEngine.resetWeekIfNeeded()
        ruleEngine.generateViolations(for: event.timestamp)
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
    @StateObject private var languageManager = AppLanguageManager.shared

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
                        Text("\(Int(selectedSuggestion.calories)) \(LocalizationHelper.localized("ккал", table: "Localizable", language: languageManager.effectiveLanguage))")
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
