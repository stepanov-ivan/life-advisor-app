import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealWindow.order) private var windows: [MealWindow]
    @StateObject private var notificationManager = NotificationManager.shared

    @State private var selectedWindow: String?
    @State private var editingEvent: MealEvent?
    @State private var logText = ""

    var todayEvents: [MealEvent] {
        let start = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<MealEvent>(
            predicate: #Predicate { $0.timestamp >= start },
            sortBy: [SortDescriptor(\MealEvent.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
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
                LogSheetView(windowLabel: window, logText: $logText) {
                    saveMealEvent(windowLabel: window)
                    selectedWindow = nil
                }
            }
            .sheet(item: $editingEvent) { event in
                MealEventEditorView(event: event)
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

    private func saveMealEvent(windowLabel: String) {
        let text = logText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        clearRecommendationCacheForToday()

        let event: MealEvent
        if let existing = latestEvent(for: windowLabel) {
            event = existing
            event.rawText = text
            event.status = .pendingEstimation
            event.parseErrorSummary = nil
            event.memoryApplied = false
            print("Meal upsert: update existing event for \(windowLabel), id=\(existing.persistentModelID)")
        } else {
            let created = MealEvent(windowLabel: windowLabel, status: .pendingEstimation, rawText: text)
            modelContext.insert(created)
            event = created
            print("Meal upsert: create new event for \(windowLabel), id=\(created.persistentModelID)")
        }
        try? modelContext.save()

        Task {
            await estimate(event: event, replacingExistingItems: true)
        }
    }

    @MainActor
    private func estimate(event: MealEvent, replacingExistingItems: Bool) async {
        guard let text = event.rawText, !text.isEmpty else { return }

        let fingerprint = normalizedFingerprint(from: text)
        let memory = findMemory(for: fingerprint)

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

            let totals = EstimationRuntime.applyMemoryPrior(totals: result.parsed.totals, memory: memory)

            event.applyTotals(calories: totals.calories, proteins: totals.proteins, fats: totals.fats, carbs: totals.carbs)
            event.status = .structured
            event.confidence = result.parsed.confidence
            event.sourceMode = result.parsed.mode == "ingredient_breakdown" ? .ingredientBreakdown : .compositeItem
            event.modelId = result.parsed.modelId
            event.promptVersion = result.parsed.promptVersion
            event.estimationSchemaVersion = result.parsed.estimationSchemaVersion
            event.rawPayload = result.rawPayload
            event.rawPayloadCreatedAt = Date()
            event.parseErrorSummary = nil
            event.memoryApplied = memory != nil
            try? modelContext.save()
            print("Meal estimate saved: \(event.windowLabel), status=\(event.status.rawValue), kcal=\(event.calories)")
        } catch {
            event.status = .parseFailed
            event.parseErrorSummary = error.localizedDescription
            event.rawPayloadCreatedAt = Date()
            try? modelContext.save()
            print("Meal estimate failed: \(event.windowLabel), error=\(error.localizedDescription)")
        }
    }

    private func createSkippedEvent(windowLabel: String) {
        guard latestEvent(for: windowLabel) == nil else { return }
        clearRecommendationCacheForToday()

        let event = MealEvent(windowLabel: windowLabel, status: .skipped)
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
        let events = todayEvents.filter { labels.contains($0.windowLabel) }

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

    private func normalizedFingerprint(from text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^a-zа-я0-9\\s]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .sorted()
            .joined(separator: " ")
    }

    private func findMemory(for fingerprint: String) -> EstimationMemory? {
        let descriptor = FetchDescriptor<EstimationMemory>(predicate: #Predicate { $0.fingerprint == fingerprint })
        return try? modelContext.fetch(descriptor).first
    }

    private func latestEvent(for windowLabel: String) -> MealEvent? {
        todayEvents.first(where: { $0.windowLabel == windowLabel })
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
                        if let confidence = event.confidence {
                            Text("Уверенность: \(confidence)")
                                .font(.caption2)
                                .foregroundColor(confidence == "low" ? .orange : .secondary)
                        }
                        if event.memoryApplied {
                            Text("Применена память прошлых правок")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
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
        var calories: String
        var proteins: String
        var fats: String
        var carbs: String
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let event: MealEvent

    @State private var textDraft = ""
    @State private var isSubmitting = false
    @State private var errorText = ""
    @State private var itemDrafts: [ItemDraft] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Текст") {
                    TextField("Что съели?", text: $textDraft, axis: .vertical)
                        .lineLimit(3...8)
                }

                if event.status == .structured && EstimationRuntime.lowConfidenceWarningVisible(event.confidence) {
                    Section {
                        Text("Оценка с низкой уверенностью. Можно уточнить текст.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                if !errorText.isEmpty {
                    Section {
                        Text(errorText).foregroundColor(.red)
                    }
                }

                Section("Ручная корректировка по позициям") {
                    if itemDrafts.isEmpty {
                        Text("Нет позиций для редактирования. Сначала выполните оценку.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach($itemDrafts) { $draft in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(draft.item.name).font(.subheadline.bold())
                                HStack {
                                    TextField("ккал", text: $draft.calories).keyboardType(.decimalPad)
                                    TextField("Б", text: $draft.proteins).keyboardType(.decimalPad)
                                    TextField("Ж", text: $draft.fats).keyboardType(.decimalPad)
                                    TextField("У", text: $draft.carbs).keyboardType(.decimalPad)
                                }
                            }
                        }

                        Button("Применить коррекцию") {
                            applyManualCorrection()
                        }
                        .disabled(!areItemDraftsValid)
                    }
                }

                Section {
                    Button(isSubmitting ? "Отправка..." : "Сохранить и переоценить") {
                        reestimate()
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
                            calories: String(Int(item.estimatedCalories)),
                            proteins: String(Int(item.estimatedProteins)),
                            fats: String(Int(item.estimatedFats)),
                            carbs: String(Int(item.estimatedCarbs))
                        )
                    }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Готово") { dismiss() }
                }
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

        }

        let totals = EstimationRuntime.aggregateTotals(items: event.estimateItems)

        event.applyTotals(calories: totals.calories, proteins: totals.proteins, fats: totals.fats, carbs: totals.carbs)
        event.memoryApplied = false
        saveMemoryPrior(
            for: event.rawText ?? "",
            calories: totals.calories,
            proteins: totals.proteins,
            fats: totals.fats,
            carbs: totals.carbs
        )
        try? modelContext.save()
    }

    private var areItemDraftsValid: Bool {
        !itemDrafts.isEmpty && itemDrafts.allSatisfy {
            Double($0.calories) != nil &&
            Double($0.proteins) != nil &&
            Double($0.fats) != nil &&
            Double($0.carbs) != nil
        }
    }

    private func saveMemoryPrior(for text: String, calories: Double, proteins: Double, fats: Double, carbs: Double) {
        let fingerprint = text.lowercased()
            .replacingOccurrences(of: "[^a-zа-я0-9\\s]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .sorted()
            .joined(separator: " ")
        guard !fingerprint.isEmpty else { return }

        let descriptor = FetchDescriptor<EstimationMemory>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.calories = calories
            existing.proteins = proteins
            existing.fats = fats
            existing.carbs = carbs
            existing.updatedAt = Date()
        } else {
            modelContext.insert(
                EstimationMemory(
                    fingerprint: fingerprint,
                    calories: calories,
                    proteins: proteins,
                    fats: fats,
                    carbs: carbs
                )
            )
        }
    }
}

struct LogSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let windowLabel: String
    @Binding var logText: String
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Что съели?", text: $logText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4...8)

                Button("Готово") {
                    onSave()
                    dismiss()
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
