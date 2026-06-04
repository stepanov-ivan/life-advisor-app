import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("llm_endpoint") private var endpoint = ""
    @AppStorage("llm_model") private var model = ""
    @AppStorage("goal_calories") private var goalCalories = 2000.0
    @AppStorage("goal_mode") private var goalMode = "calories"

    @State private var apiKey = ""
    @State private var currentStep = 0
    @StateObject private var languageManager = AppLanguageManager.shared

    var body: some View {
        VStack {
            TabView(selection: $currentStep) {
                llmStep.tag(0)
                goalStep.tag(1)
                windowsStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(currentStep < 2 ? "Далее" : "Начать") {
                if currentStep < 2 {
                    currentStep += 1
                } else {
                    completeOnboarding()
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 40)
        }
    }

    private var llmStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Подключите LLM")
                .font(.title.bold())

            Text("Введите данные вашего AI-провайдера.\nЭто как в Cursor — endpoint, ключ и модель.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                TextField("Endpoint (https://api.openai.com/v1)", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .keyboardType(.URL)

                SecureField("API-ключ", text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                TextField("Модель (gpt-4o-mini)", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
            }
            .padding(.horizontal, 32)
        }
        .padding()
    }

    private var goalStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "target")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Ваша цель")
                .font(.title.bold())

            Text("Укажите дневную норму калорий.\nПоддерживается только здоровый дефицит.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Picker("Режим", selection: $goalMode) {
                Text("Калории").tag("calories")
                Text("Калькулятор").tag("calculator")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)

            if goalMode == "calories" {
                HStack {
                    TextField("2000", value: $goalCalories, format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .multilineTextAlignment(.center)
                    Text("ккал/день")
                }
            } else {
                OnboardingCalculatorView { result in
                    goalCalories = result
                }
            }
        }
        .padding()
    }

    private var windowsStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.badge")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Окна питания")
                .font(.title.bold())

            Text("Стандартные окна можно изменить.\nУведомления помогут не забыть записать приём пищи.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                WindowRow(label: LocalizationHelper.localized("breakfast_name", table: "Localizable", language: languageManager.effectiveLanguage), time: "7:00 – 10:00")
                WindowRow(label: LocalizationHelper.localized("lunch_name", table: "Localizable", language: languageManager.effectiveLanguage), time: "12:00 – 15:00")
                WindowRow(label: LocalizationHelper.localized("dinner_name", table: "Localizable", language: languageManager.effectiveLanguage), time: "18:00 – 21:00")
            }
            .padding(.horizontal, 32)

            Text("Подробная настройка окон — в настройках приложения")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private func completeOnboarding() {
        KeychainHelper.save(key: "llm_api_key", value: apiKey)
        hasCompletedOnboarding = true
    }
}

struct WindowRow: View {
    let label: String
    let time: String

    var body: some View {
        HStack {
            Text(label)
                .fontWeight(.medium)
            Spacer()
            Text(time)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct OnboardingCalculatorView: View {
    @State private var gender = "male"
    @State private var age = "30"
    @State private var height = "180"
    @State private var weight = "80"
    @State private var activityLevel = "moderate"
    @State private var result: Double?
    let onResult: (Double) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Picker("Пол", selection: $gender) {
                Text("Мужской").tag("male")
                Text("Женский").tag("female")
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Возраст")
                TextField("30", text: $age)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Рост (см)")
                TextField("180", text: $height)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                Text("Вес (кг)")
                TextField("80", text: $weight)
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
                calculateAndApply()
            }
            .buttonStyle(.bordered)

            if let result = result {
                Text("Рекомендуемая норма: \(Int(result)) ккал/день")
                    .font(.headline)
                    .foregroundColor(.green)
            }
        }
    }

    private func calculateAndApply() {
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
        let goal = (tdee * 0.85).rounded()
        result = goal
        onResult(goal)
    }
}
