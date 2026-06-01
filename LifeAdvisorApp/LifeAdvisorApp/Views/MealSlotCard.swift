import SwiftUI

struct MealSlotCard: View {
    let windowLabel: String
    let timeRange: String
    let event: MealEvent?
    let violations: [RuleViolation]
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(windowLabel).font(.headline)
                Spacer()
                if violations.count > 0 {
                    Text("\(violations.count)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: violations.isEmpty ? 0 : 3)
        )
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

    private var borderColor: Color {
        let hasViolation = violations.contains { $0.zone == "violation" }
        return hasViolation ? .red : .yellow
    }
}
