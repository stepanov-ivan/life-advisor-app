import SwiftUI
import SwiftData
import Charts

struct RuleDetailView: View {
    let rule: RuleDefinition
    @Environment(\.modelContext) private var modelContext
    @State private var engine = RuleEngine()
    @Binding var selectedDate: Date
    @Binding var selectedTab: Int

    @State private var weeklyValues: [(date: Date, value: Double?)] = []
    @State private var violations: [RuleViolation] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Description
                Text(rule.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                // Chart
                chartSection
                    .frame(height: 220)
                    .padding(.horizontal)

                // Thresholds legend
                thresholdsLegend
                    .padding(.horizontal)

                // Violations list
                if !violations.isEmpty {
                    Text("Нарушения")
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(violations) { violation in
                        violationRow(violation)
                            .padding(.horizontal)
                    }
                } else if !weeklyValues.isEmpty {
                    Text("Нарушений нет")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(rule.title)
        .onAppear {
            engine.configure(context: modelContext)
            loadData()
        }
    }

    // MARK: - Chart

    private var chartSection: some View {
        let lower = rule.params.lower
        let upper = rule.params.upper

        return Chart {
            // Warning zones
            if let upper = upper {
                RectangleMark(
                    xStart: .value("Start", weeklyValues.first?.date ?? Date()),
                    xEnd: .value("End", weeklyValues.last?.date ?? Date()),
                    yStart: .value("WarnLow", upper * rule.warningRatio),
                    yEnd: .value("WarnHigh", upper)
                )
                .foregroundStyle(.yellow.opacity(0.15))
            }
            if let lower = lower {
                RectangleMark(
                    xStart: .value("Start", weeklyValues.first?.date ?? Date()),
                    xEnd: .value("End", weeklyValues.last?.date ?? Date()),
                    yStart: .value("WarnLow", lower),
                    yEnd: .value("WarnHigh", lower / rule.warningRatio)
                )
                .foregroundStyle(.yellow.opacity(0.15))
            }

            // Threshold lines
            if let upper = upper {
                RuleMark(y: .value("Upper", upper))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.red.opacity(0.5))
            }
            if let lower = lower {
                RuleMark(y: .value("Lower", lower))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.red.opacity(0.5))
            }

            // Value line
            ForEach(weeklyValues, id: \.date) { point in
                if let value = point.value {
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(.blue)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(zoneColorFor(value: value))
                    .symbolSize(30)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
    }

    private func zoneColorFor(value: Double) -> Color {
        let result = evaluateRange(value: value, lower: rule.params.lower, upper: rule.params.upper, warningRatio: rule.warningRatio)
        switch result.zone {
        case .normal: return .green
        case .warning: return .yellow
        case .violation: return .red
        case .noData: return .gray
        }
    }

    // MARK: - Thresholds

    private var thresholdsLegend: some View {
        HStack(spacing: 16) {
            if let lower = rule.params.lower {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Мин: \(String(format: "%.0f", lower))")
                        .font(.caption)
                }
            }
            if let upper = rule.params.upper {
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Макс: \(String(format: "%.0f", upper))")
                        .font(.caption)
                }
            }
            Spacer()
        }
    }

    // MARK: - Violation rows

    private func violationRow(_ violation: RuleViolation) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMM"

        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if let item = violation.estimateItem {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(item.name)
                            .font(.subheadline)
                    }
                }
                Text("Причина: \(violation.reasonCode)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Отклонение: \(String(format: "%.1f", violation.magnitude))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let meal = violation.mealEvent {
                    Button("Открыть приём") {
                        selectedDate = meal.timestamp
                        selectedTab = 0
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack {
                Circle()
                    .fill(violation.zone == "violation" ? Color.red : Color.yellow)
                    .frame(width: 8, height: 8)
                Text(formatter.string(from: violation.date))
                    .font(.subheadline)
                Spacer()
                Text(violation.zone == "violation" ? "Нарушено" : "Внимание")
                    .font(.caption)
                    .foregroundColor(violation.zone == "violation" ? .red : .yellow)
            }
        }
    }

    // MARK: - Data loading

    private func loadData() {
        let cal = Calendar.current
        let weekStart = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        ) ?? Date()

        weeklyValues = (0..<7).compactMap { dayOffset in
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: weekStart) else { return nil }
            let result = engine.evaluateRule(rule, for: date)

            var value: Double?
            if result.zone != .noData, let field = rule.field {
                // Get raw value for chart
                value = engineRawValue(field: field, for: date)
            }
            return (date, value)
        }

        violations = engine.ruleViolationsForWeek(ruleId: rule.id, weekStart: weekStart)
    }

    private func engineRawValue(field: String, for date: Date) -> Double? {
        let range = DashboardDateLogic.dayRange(for: date)
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<MealEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end }
        )
        let events = (try? modelContext.fetch(descriptor)) ?? []
        let items = events
            .filter { $0.status != .skipped && $0.status != .parseFailed }
            .flatMap { $0.estimateItems }

        switch field {
        case "fatPercent":
            let cals = items.reduce(0) { $0 + $1.estimatedCalories }
            let fats = items.reduce(0) { $0 + $1.estimatedFats }
            return cals > 0 ? (fats * 9) / cals : nil
        case "proteinPercent":
            let cals = items.reduce(0) { $0 + $1.estimatedCalories }
            let proteins = items.reduce(0) { $0 + $1.estimatedProteins }
            return cals > 0 ? (proteins * 4) / cals : nil
        case "saturatedFatPercent":
            let cals = items.reduce(0) { $0 + $1.estimatedCalories }
            let sf = items.reduce(0) { $0 + $1.estimatedSaturatedFats }
            return cals > 0 ? (sf * 9) / cals : nil
        case "carbsPercent":
            let cals = items.reduce(0) { $0 + $1.estimatedCalories }
            let carbs = items.reduce(0) { $0 + $1.estimatedCarbs }
            return cals > 0 ? (carbs * 4) / cals : nil
        case "sugarPercent":
            let cals = items.reduce(0) { $0 + $1.estimatedCalories }
            let sugar = items.reduce(0) { $0 + $1.estimatedSugar }
            return cals > 0 ? (sugar * 4) / cals : nil
        case "sodiumMg":
            return items.reduce(0) { $0 + $1.estimatedSodium }
        case "fiberGrams":
            return items.reduce(0) { $0 + $1.estimatedFiber }
        case "fruitVegGrams":
            return items
                .filter { $0.foodCategory == "fruit" || $0.foodCategory == "vegetable" }
                .reduce(0) { $0 + $1.grams }
        case "redMeatGrams":
            return items
                .filter { $0.foodCategory == "red_meat" }
                .reduce(0) { $0 + $1.grams }
        case "energyBalancePercent":
            let cals = items.reduce(0) { $0 + $1.estimatedCalories }
            let target = UserDefaults.standard.double(forKey: "daily_calorie_target")
            return target > 0 ? (cals - target) / target : nil
        default:
            return nil
        }
    }
}
