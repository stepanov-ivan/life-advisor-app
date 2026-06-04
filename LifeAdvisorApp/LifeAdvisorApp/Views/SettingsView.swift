import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MealWindow.order) private var windows: [MealWindow]
    @Query(sort: \MemorySuggestion.lastUsedAt, order: .reverse) private var memorySuggestions: [MemorySuggestion]
    @Query(sort: \MemoryHypothesis.lastSeenAt, order: .reverse) private var memoryHypotheses: [MemoryHypothesis]
    @Query(sort: \MemoryDataGap.updatedAt, order: .reverse) private var memoryDataGaps: [MemoryDataGap]

    @AppStorage("llm_endpoint") private var endpoint = ""
    @AppStorage("llm_model") private var model = ""
    @State private var apiKey = ""
    @AppStorage("goal_calories") private var goalCalories = 2000.0
    @AppStorage("goal_mode") private var goalMode = "calories"
    @State private var showCalculator = false

    @StateObject private var languageManager = AppLanguageManager.shared

    @State private var newWindowName = ""
    @State private var newStartTime = Date()
    @State private var newEndTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var showWipeMemoryConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                llmSection
                goalSection
                languageSection
                windowsSection
                memorySection
            }
            .navigationTitle("Настройки")
            .onAppear {
                apiKey = KeychainHelper.read(key: "llm_api_key") ?? ""
            }
        }
    }

    private var languageSection: some View {
        Section("Язык") {
            Picker("Язык", selection: Binding(
                get: { languageManager.override },
                set: { languageManager.setOverride($0) }
            )) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Text(LocalizationHelper.localized(lang.displayNameKey, table: "Localizable", language: languageManager.effectiveLanguage)).tag(lang)
                }
            }
        }
    }

    private var memorySection: some View {
        Section("Память") {
            if memorySuggestions.isEmpty && memoryHypotheses.isEmpty && memoryDataGaps.isEmpty {
                Text("Память пока пустая")
                    .foregroundColor(.secondary)
            }

            if !memorySuggestions.isEmpty {
                Text("Шаблоны")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(memorySuggestions.prefix(10)) { suggestion in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(suggestion.displayText)
                            Text("\(Int(suggestion.calories)) ккал")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            MemoryEngine.deleteMemorySuggestion(suggestion, context: modelContext)
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }

            if !memoryHypotheses.isEmpty {
                Text("Гипотезы")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(memoryHypotheses.prefix(10)) { hypothesis in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(hypothesis.title)
                            Text(hypothesis.status.rawValue)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            MemoryEngine.deleteHypothesis(hypothesis, context: modelContext)
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }

            if !memoryDataGaps.isEmpty {
                Text("Data-gap")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(memoryDataGaps.prefix(10)) { gap in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(gap.title)
                            Text(gap.itemFingerprint)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            MemoryEngine.deleteDataGap(gap, context: modelContext)
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }

            Button("Сбросить всю память", role: .destructive) {
                showWipeMemoryConfirm = true
            }
            .confirmationDialog("Удалить все memory-записи?", isPresented: $showWipeMemoryConfirm) {
                Button("Удалить всё", role: .destructive) {
                    MemoryEngine.wipeAllMemory(context: modelContext)
                    try? modelContext.save()
                }
                Button("Отмена", role: .cancel) { }
            }
        }
    }

    private var llmSection: some View {
        Section("LLM") {
            TextField("Endpoint", text: $endpoint)
                .keyboardType(.URL)
                .autocapitalization(.none)
            SecureField("API-ключ", text: $apiKey)
                .onChange(of: apiKey) { _, newValue in
                    KeychainHelper.save(key: "llm_api_key", value: newValue)
                }
            TextField("Модель", text: $model)
                .autocapitalization(.none)
        }
    }

    private var goalSection: some View {
        Section("Цель") {
            Picker("Режим", selection: $goalMode) {
                Text("Калории").tag("calories")
                Text("Калькулятор").tag("calculator")
            }

            if goalMode == "calories" {
                HStack {
                    Text("Калории в день")
                    Spacer()
                    TextField("", value: $goalCalories, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("ккал")
                }
            } else {
                Button("Пересчитать через калькулятор") {
                    showCalculator = true
                }
            }
        }
        .sheet(isPresented: $showCalculator) {
            CalculatorView { result in
                goalCalories = result
                showCalculator = false
            }
        }
    }

    private var windowsSection: some View {
        Section("Окна питания") {
            if windows.isEmpty {
                Text("Нет окон питания")
                    .foregroundColor(.secondary)
            }

            ForEach(windows.sorted(by: { $0.order < $1.order })) { window in
                VStack(alignment: .leading, spacing: 8) {
                    if window.isSystemDefault {
                        Text(window.localizedName(language: languageManager.effectiveLanguage))
                            .font(.headline)
                    } else {
                        TextField("Название", text: Binding(
                            get: { window.name },
                            set: { newValue in
                                window.name = newValue
                                persistWindowsAndReschedule()
                            }
                        ))
                    }

                    HStack {
                        DatePicker(
                            "Начало",
                            selection: Binding(
                                get: { dateFrom(hour: window.startHour, minute: window.startMinute) },
                                set: { newValue in
                                    let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                    window.startHour = components.hour ?? window.startHour
                                    window.startMinute = components.minute ?? window.startMinute
                                    persistWindowsAndReschedule()
                                }
                            ),
                            displayedComponents: [.hourAndMinute]
                        )

                        DatePicker(
                            "Конец",
                            selection: Binding(
                                get: { dateFrom(hour: window.endHour, minute: window.endMinute) },
                                set: { newValue in
                                    let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                                    window.endHour = components.hour ?? window.endHour
                                    window.endMinute = components.minute ?? window.endMinute
                                    persistWindowsAndReschedule()
                                }
                            ),
                            displayedComponents: [.hourAndMinute]
                        )
                    }
                }
            }
            .onDelete(perform: deleteWindows)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Новое окно", text: $newWindowName)
                HStack {
                    DatePicker("Начало", selection: $newStartTime, displayedComponents: [.hourAndMinute])
                    DatePicker("Конец", selection: $newEndTime, displayedComponents: [.hourAndMinute])
                }
                Button("Добавить окно") {
                    addWindow()
                }
                .disabled(!canAddWindow)

                if windows.count >= 6 {
                    Text("Максимум 6 окон питания")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var canAddWindow: Bool {
        !newWindowName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && windows.count < 6
    }

    private func addWindow() {
        guard canAddWindow else { return }

        let start = Calendar.current.dateComponents([.hour, .minute], from: newStartTime)
        let end = Calendar.current.dateComponents([.hour, .minute], from: newEndTime)

        let window = MealWindow(
            windowId: UUID().uuidString,
            name: newWindowName.trimmingCharacters(in: .whitespacesAndNewlines),
            startHour: start.hour ?? 7,
            startMinute: start.minute ?? 0,
            endHour: end.hour ?? 10,
            endMinute: end.minute ?? 0,
            order: windows.count
        )
        modelContext.insert(window)
        persistWindowsAndReschedule()

        newWindowName = ""
    }

    private func deleteWindows(at offsets: IndexSet) {
        let sorted = windows.sorted(by: { $0.order < $1.order })
        for index in offsets {
            modelContext.delete(sorted[index])
        }

        let remaining = sorted.enumerated().filter { !offsets.contains($0.offset) }.map { $0.element }
        for (index, window) in remaining.enumerated() {
            window.order = index
        }

        persistWindowsAndReschedule()
    }

    private func persistWindowsAndReschedule() {
        try? modelContext.save()
        NotificationManager.shared.scheduleMealWindowNotifications(windows: windows.sorted(by: { $0.order < $1.order }))
    }

    private func dateFrom(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
}

struct CalculatorView: View {
    @State private var gender = "male"
    @State private var age = "30"
    @State private var height = "180"
    @State private var weight = "80"
    @State private var activityLevel = "moderate"
    let onResult: (Double) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Пол", selection: $gender) {
                    Text("Мужской").tag("male")
                    Text("Женский").tag("female")
                }

                HStack {
                    Text("Возраст")
                    TextField("", text: $age)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Рост (см)")
                    TextField("", text: $height)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Вес (кг)")
                    TextField("", text: $weight)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }

                Picker("Активность", selection: $activityLevel) {
                    Text("Сидячий").tag("sedentary")
                    Text("Лёгкая").tag("light")
                    Text("Средняя").tag("moderate")
                    Text("Активный").tag("active")
                    Text("Спортивный").tag("athlete")
                }

                Button("Рассчитать") {
                    calculate()
                }
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Калькулятор")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private func calculate() {
        guard let h = Double(height), let w = Double(weight), let a = Int(age) else { return }

        let bmr: Double
        if gender == "male" {
            bmr = 10 * w + 6.25 * h - 5 * Double(a) + 5
        } else {
            bmr = 10 * w + 6.25 * h - 5 * Double(a) - 161
        }

        let multiplier: Double
        switch activityLevel {
        case "sedentary": multiplier = 1.2
        case "light": multiplier = 1.375
        case "moderate": multiplier = 1.55
        case "active": multiplier = 1.725
        case "athlete": multiplier = 1.9
        default: multiplier = 1.55
        }

        let tdee = bmr * multiplier
        let goal = tdee * 0.85
        onResult(goal.rounded())
    }
}
