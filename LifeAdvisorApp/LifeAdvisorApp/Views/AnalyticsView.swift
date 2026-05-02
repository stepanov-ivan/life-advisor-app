import SwiftUI
import SwiftData
import Charts

struct AnalyticsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("goal_calories") private var goalCalories = 2000.0
    @State private var selectedPeriod: AnalyticsPeriod = .day

    enum AnalyticsPeriod: String, CaseIterable {
        case day = "День"
        case week = "Неделя"
        case month = "Месяц"
    }

    private var periodInterval: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        switch selectedPeriod {
        case .day:
            return (calendar.startOfDay(for: now), now)
        case .week:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return (startOfWeek, now)
        case .month:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            return (startOfMonth, now)
        }
    }

    private var events: [MealEvent] {
        let (start, end) = periodInterval
        let descriptor = FetchDescriptor<MealEvent>(
            predicate: #Predicate {
                $0.timestamp >= start && $0.timestamp <= end &&
                $0.statusRaw != "empty" && $0.statusRaw != "skipped"
            },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private var caloriesSum: Double {
        events.reduce(0) { $0 + $1.calories }
    }

    private var proteinsSum: Double {
        events.reduce(0) { $0 + $1.proteins }
    }

    private var fatsSum: Double {
        events.reduce(0) { $0 + $1.fats }
    }

    private var carbsSum: Double {
        events.reduce(0) { $0 + $1.carbs }
    }

    private var deficit: Double {
        let daysInPeriod = max(1, Calendar.current.dateComponents([.day], from: periodInterval.start, to: periodInterval.end).day ?? 1)
        return goalCalories * Double(daysInPeriod) - caloriesSum
    }

    private var groupedByDay: [(date: Date, calories: Double, proteins: Double, fats: Double, carbs: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: events) { calendar.startOfDay(for: $0.timestamp) }
        return grouped.map { (date, dayEvents) in
            (
                date: date,
                calories: dayEvents.reduce(0) { $0 + $1.calories },
                proteins: dayEvents.reduce(0) { $0 + $1.proteins },
                fats: dayEvents.reduce(0) { $0 + $1.fats },
                carbs: dayEvents.reduce(0) { $0 + $1.carbs }
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var distributionByWindow: [(window: String, calories: Double)] {
        let grouped = Dictionary(grouping: events) { $0.windowLabel }
        return grouped.map { (window, windowEvents) in
            (window: window, calories: windowEvents.reduce(0) { $0 + $1.calories })
        }
        .sorted { $0.calories > $1.calories }
    }

    private var xAxisDateFormat: Date.FormatStyle {
        switch selectedPeriod {
        case .day:
            return .dateTime.hour().minute()
        case .week:
            return .dateTime.weekday(.abbreviated)
        case .month:
            return .dateTime.day()
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Период", selection: $selectedPeriod) {
                    ForEach(AnalyticsPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if events.isEmpty {
                    emptyView
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            caloriesCard
                            bjuCard
                            deficitCard
                            distributionCard
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Аналитика")
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Нет данных за выбранный период")
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var caloriesCard: some View {
        NavigationLink {
            CalorieDetailView(
                title: "Калории",
                groupedData: groupedByDay,
                goal: goalCalories,
                unit: "ккал"
            )
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Калории")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(caloriesSum))")
                        .font(.title.bold())
                    Text("ккал")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Цель: \(Int(goalCalories * Double(max(1, groupedByDay.count))))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !groupedByDay.isEmpty {
                    Chart(groupedByDay, id: \.date) { item in
                        BarMark(
                            x: .value("Дата", item.date, unit: .day),
                            y: .value("Калории", item.calories)
                        )
                        .foregroundStyle(Color.orange.gradient)
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: xAxisDateFormat)
                        }
                    }
                    .frame(height: 160)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5)
        }
    }

    @ViewBuilder
    private var bjuCard: some View {
        NavigationLink {
            BJUDetailView(
                groupedData: groupedByDay,
                proteinsSum: proteinsSum,
                fatsSum: fatsSum,
                carbsSum: carbsSum
            )
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("БЖУ")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 0) {
                    if caloriesSum > 0 {
                        let pctP = proteinsSum * 4 / caloriesSum * 100
                        let pctF = fatsSum * 9 / caloriesSum * 100
                        let pctC = carbsSum * 4 / caloriesSum * 100

                        barSegment(value: pctP, color: .blue, label: "Б \(Int(proteinsSum))г")
                        barSegment(value: pctF, color: .yellow, label: "Ж \(Int(fatsSum))г")
                        barSegment(value: pctC, color: .green, label: "У \(Int(carbsSum))г")
                    }
                }
                .frame(height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                HStack(spacing: 16) {
                    legendDot(color: .blue, text: "Белки \(Int(proteinsSum))г")
                    legendDot(color: .yellow, text: "Жиры \(Int(fatsSum))г")
                    legendDot(color: .green, text: "Углеводы \(Int(carbsSum))г")
                }
                .font(.caption)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5)
        }
    }

    @ViewBuilder
    private var deficitCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Дефицит")
                .font(.headline)

            HStack(alignment: .firstTextBaseline) {
                Text(deficit >= 0 ? "−\(Int(deficit))" : "+\(Int(-deficit))")
                    .font(.title.bold())
                    .foregroundColor(deficitColor)
                Text("ккал")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(deficitLabel)
                    .font(.caption)
                    .foregroundColor(deficitColor)
            }

            let goalForPeriod = goalCalories * Double(max(1, groupedByDay.count))
            if goalForPeriod > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(deficitColor.opacity(0.5))
                            .frame(
                                width: min(geo.size.width, geo.size.width * max(0, min(1, caloriesSum / goalForPeriod))),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }

    @ViewBuilder
    private var distributionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Распределение по окнам")
                .font(.headline)

            if caloriesSum > 0 {
                Chart(distributionByWindow, id: \.window) { item in
                    SectorMark(
                        angle: .value("Калории", item.calories),
                        innerRadius: .ratio(0.5),
                        angularInset: 1
                    )
                    .foregroundStyle(by: .value("Окно", item.window))
                }
                .frame(height: 180)

                VStack(spacing: 6) {
                    ForEach(distributionByWindow, id: \.window) { item in
                        HStack {
                            Circle()
                                .fill(Color.blue.opacity(0.6))
                                .frame(width: 8, height: 8)
                            Text(item.window)
                                .font(.caption)
                            Spacer()
                            Text("\(Int(item.calories / max(1, caloriesSum) * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }

    private func barSegment(value: Double, color: Color, label: String) -> some View {
        color
            .frame(width: value > 0 ? nil : 0)
            .overlay {
                if value > 15 {
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(.white)
                }
            }
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
        }
    }

    private var deficitColor: Color {
        let daysInPeriod = max(1, Calendar.current.dateComponents([.day], from: periodInterval.start, to: periodInterval.end).day ?? 1)
        let upperBound = goalCalories * Double(daysInPeriod) * 1.15
        let lowerBound = goalCalories * Double(daysInPeriod) * 0.85
        if caloriesSum > upperBound { return .red }
        if caloriesSum < lowerBound { return .orange }
        return .green
    }

    private var deficitLabel: String {
        let daysInPeriod = max(1, Calendar.current.dateComponents([.day], from: periodInterval.start, to: periodInterval.end).day ?? 1)
        let upperBound = goalCalories * Double(daysInPeriod) * 1.15
        let lowerBound = goalCalories * Double(daysInPeriod) * 0.85
        if caloriesSum > upperBound { return "Перебор" }
        if caloriesSum < lowerBound { return "Недобор" }
        return "В норме"
    }
}

struct CalorieDetailView: View {
    let title: String
    let groupedData: [(date: Date, calories: Double, proteins: Double, fats: Double, carbs: Double)]
    let goal: Double
    let unit: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            Chart(groupedData, id: \.date) { item in
                BarMark(
                    x: .value("Дата", item.date, unit: .day),
                    y: .value(unit, item.calories)
                )
                .foregroundStyle(Color.orange.gradient)
            }
            .frame(height: 300)
            .padding()

            Chart(groupedData, id: \.date) { item in
                RuleMark(y: .value("Цель", goal))
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5]))

                LineMark(
                    x: .value("Дата", item.date, unit: .day),
                    y: .value(unit, item.calories)
                )
                .foregroundStyle(Color.orange)
            }
            .frame(height: 200)
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BJUDetailView: View {
    let groupedData: [(date: Date, calories: Double, proteins: Double, fats: Double, carbs: Double)]
    let proteinsSum: Double
    let fatsSum: Double
    let carbsSum: Double

    var body: some View {
        VStack {
            Chart(groupedData, id: \.date) { item in
                BarMark(
                    x: .value("Дата", item.date, unit: .day),
                    y: .value("Белки", item.proteins)
                )
                .foregroundStyle(Color.blue)
                BarMark(
                    x: .value("Дата", item.date, unit: .day),
                    y: .value("Жиры", item.fats)
                )
                .foregroundStyle(Color.yellow)
                BarMark(
                    x: .value("Дата", item.date, unit: .day),
                    y: .value("Углеводы", item.carbs)
                )
                .foregroundStyle(Color.green)
            }
            .frame(height: 300)
            .padding()

            HStack(spacing: 32) {
                VStack {
                    Text("\(Int(proteinsSum))")
                        .font(.title2.bold())
                    Text("Белки (г)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                VStack {
                    Text("\(Int(fatsSum))")
                        .font(.title2.bold())
                    Text("Жиры (г)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                VStack {
                    Text("\(Int(carbsSum))")
                        .font(.title2.bold())
                    Text("Углеводы (г)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("БЖУ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
