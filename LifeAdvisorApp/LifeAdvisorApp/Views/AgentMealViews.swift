import SwiftUI

struct AgentChatInputSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isPlanning: Bool
    let onSubmit: (String) -> Void

    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Опиши, что ты съел или что нужно исправить.")
                    .font(.headline)

                TextField("Например: сегодня ел овсянку, кефир и смэшбургер", text: $text, axis: .vertical)
                    .lineLimit(4...8)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isPlanning)

                if isPlanning {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Агент строит план...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Button {
                    onSubmit(text)
                } label: {
                    Text(isPlanning ? "Планирую..." : "Продолжить")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || isPlanning)

                Spacer()
            }
            .padding()
            .navigationTitle("Агент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .disabled(isPlanning)
                }
            }
        }
    }
}

struct MealExecutionBottomBar: View {
    let session: MealExecutionSession
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("План: \(session.scenario == .create ? "создание" : "редактирование")")
                    .font(.caption.bold())
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(groupedSteps.enumerated()), id: \.offset) { _, group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                ForEach(group.steps) { step in
                                    Circle()
                                        .fill(color(for: step))
                                        .frame(width: 12, height: 12)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
        .padding(.bottom, 12)
    }

    private var groupedSteps: [(title: String, steps: [MealExecutionStep])] {
        Dictionary(grouping: session.steps) { DashboardDateLogic.dayKey(for: $0.day) }
            .keys
            .sorted()
            .map { key in
                let date = DashboardDateLogic.date(from: key) ?? Date()
                return (
                    title: date.formatted(date: .abbreviated, time: .omitted),
                    steps: session.steps.filter { DashboardDateLogic.dayKey(for: $0.day) == key }
                )
            }
    }

    private func color(for step: MealExecutionStep) -> Color {
        if step.id == session.activeStep?.id {
            return .orange
        }
        switch step.state {
        case .committed:
            return .green
        case .failed:
            return .red
        case .needsResolve:
            return .yellow
        default:
            return .gray.opacity(0.35)
        }
    }
}
