import SwiftUI
import SwiftData

struct MealSlotExecutionContext {
    let stepType: MealStepType
    let products: [MealProductDraft]
    let selectedDayLabel: String
    let selectedSlotLabel: String
    let resolveKind: MealResolveKind?
    let onNameChange: (UUID, String) -> Void
    let onGramsChange: (UUID, String) -> Void
    let onRemove: (UUID) -> Void
    let onAdd: () -> Void
    let onConfirm: () -> Void
    let onResolveToEdit: () -> Void
    let onResolveToDayOffset: (Int) -> Void
    let onResolveToWindow: (String) -> Void
}

struct MealSlotCard: View {
    let windowLabel: String
    let timeRange: String
    let event: MealEvent?
    let engine: RuleEngine
    let onTap: () -> Void
    let executionContext: MealSlotExecutionContext?
    @StateObject private var languageManager = AppLanguageManager.shared
    @State private var expandedItemId: PersistentIdentifier?

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
                    Label(LocalizationHelper.localized("Пропущено", table: "Localizable", language: languageManager.effectiveLanguage), systemImage: "slash.circle")
                        .foregroundColor(.secondary)
                case .pendingEstimation:
                    Label(event.rawText ?? LocalizationHelper.localized("Оценка...", table: "Localizable", language: languageManager.effectiveLanguage), systemImage: "clock")
                        .foregroundColor(.orange)
                case .parseFailed:
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.rawText ?? "")
                        Text(LocalizationHelper.localized("Последняя оценка не обновлена", table: "Localizable", language: languageManager.effectiveLanguage))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                case .structured:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(event.calories)) \(LocalizationHelper.localized("ккал", table: "Localizable", language: languageManager.effectiveLanguage))").font(.title3.bold())
                        Text(String(format: LocalizationHelper.localized("meal_macros_format", table: "Localizable", language: languageManager.effectiveLanguage), Int(event.proteins), Int(event.fats), Int(event.carbs)))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(event.estimateItems.prefix(5), id: \.persistentModelID) { item in
                            let sigViolations = engine.significantViolationsForItem(item, date: event.timestamp)

                            if !sigViolations.isEmpty {
                                DisclosureGroup(isExpanded: Binding(
                                    get: { expandedItemId == item.persistentModelID },
                                    set: { expandedItemId = $0 ? item.persistentModelID : nil }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(sigViolations, id: \.ruleId) { contrib in
                                            HStack(spacing: 4) {
                                                Circle()
                                                    .fill(Color.red)
                                                    .frame(width: 5, height: 5)
                                                let localizer = RulePresentationLocalizer(language: languageManager.effectiveLanguage)
                                                let rule = engine.allRules().first(where: { $0.id == contrib.ruleId })
                                                let title = rule.map { localizer.ruleTitle(for: $0.id) } ?? contrib.ruleId
                                                Text("\(title) \(contributionFormat(for: contrib, rule: rule))")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.leading, 12)
                                    .padding(.top, 2)
                                } label: {
                                    HStack {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 6, height: 6)
                                        Text(item.name).font(.caption)
                                        Spacer()
                                        Text("\(Int(item.estimatedCalories)) \(LocalizationHelper.localized("ккал", table: "Localizable", language: languageManager.effectiveLanguage))").font(.caption2)
                                    }
                                    .foregroundColor(.secondary)
                                }
                            } else {
                                HStack {
                                    Text(item.name).font(.caption)
                                    Spacer()
                                    Text("\(Int(item.estimatedCalories)) \(LocalizationHelper.localized("ккал", table: "Localizable", language: languageManager.effectiveLanguage))").font(.caption2)
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                case .empty:
                    EmptyView()
                }
            } else {
                Label(LocalizationHelper.localized("Записать приём пищи", table: "Localizable", language: languageManager.effectiveLanguage), systemImage: "plus.circle")
                    .foregroundColor(.secondary)
            }

            if let executionContext {
                Divider()
                    .padding(.top, 4)

                Text(executionContext.stepType == .create ? "Подготовленное создание" : "Подготовленное редактирование")
                    .font(.caption.bold())
                    .foregroundColor(.orange)

                HStack(spacing: 8) {
                    Label(executionContext.selectedDayLabel, systemImage: "calendar")
                    Label(executionContext.selectedSlotLabel, systemImage: "fork.knife")
                }
                .font(.caption)
                .foregroundColor(.secondary)

                ForEach(executionContext.products) { product in
                    HStack(spacing: 8) {
                        TextField("Продукт", text: Binding(
                            get: { product.name },
                            set: { executionContext.onNameChange(product.id, $0) }
                        ))
                        .textFieldStyle(.roundedBorder)

                        TextField("г", text: Binding(
                            get: { String(Int(product.grams.rounded())) },
                            set: { executionContext.onGramsChange(product.id, $0) }
                        ))
                        .keyboardType(.numberPad)
                        .frame(width: 54)
                        .textFieldStyle(.roundedBorder)

                        Button(role: .destructive) {
                            executionContext.onRemove(product.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    Text("\(Int(product.estimatedCalories)) ккал  Б \(Int(product.estimatedProteins))  Ж \(Int(product.estimatedFats))  У \(Int(product.estimatedCarbs))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Button("Добавить продукт") {
                    executionContext.onAdd()
                }
                .buttonStyle(.bordered)

                if let resolveKind = executionContext.resolveKind {
                    resolveSection(resolveKind, executionContext: executionContext)
                }

                Button("Подтвердить") {
                    executionContext.onConfirm()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(backgroundColor)
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func contributionFormat(for item: RuleContributionItem, rule: RuleDefinition?) -> String {
        RuleContributionPresentation.contributionText(
            absoluteContribution: item.absoluteContribution,
            percentContribution: item.percentContribution,
            field: rule?.field,
            language: languageManager.effectiveLanguage
        )
    }

    private var backgroundColor: Color {
        if executionContext != nil {
            return Color.orange.opacity(0.15)
        }
        guard let event else { return Color.gray.opacity(0.15) }
        switch event.status {
        case .empty: return Color.gray.opacity(0.15)
        case .pendingEstimation: return Color.yellow.opacity(0.2)
        case .structured: return Color.green.opacity(0.2)
        case .parseFailed: return Color.orange.opacity(0.2)
        case .skipped: return Color.gray.opacity(0.15)
        }
    }

    @ViewBuilder
    private func resolveSection(_ resolveKind: MealResolveKind, executionContext: MealSlotExecutionContext) -> some View {
        switch resolveKind {
        case .createConflict:
            Text("На этот день и слот запись уже существует. Можно перейти в редактирование или быстро сменить день и приём пищи.")
                .font(.caption)
                .foregroundColor(.orange)

            HStack {
                Button("Вчера") {
                    executionContext.onResolveToDayOffset(-1)
                }
                Button("Сегодня") {
                    executionContext.onResolveToDayOffset(0)
                }
                Button("Завтра") {
                    executionContext.onResolveToDayOffset(1)
                }
            }
            .buttonStyle(.bordered)

            HStack {
                Button("Завтрак") {
                    executionContext.onResolveToWindow("breakfast")
                }
                Button("Обед") {
                    executionContext.onResolveToWindow("lunch")
                }
                Button("Ужин") {
                    executionContext.onResolveToWindow("dinner")
                }
            }
            .buttonStyle(.bordered)

            Button("Редактировать существующий") {
                executionContext.onResolveToEdit()
            }
            .buttonStyle(.bordered)

        case .missingMealSlot:
            Text("Нужно выбрать слот приёма пищи, чтобы продолжить выполнение шага.")
                .font(.caption)
                .foregroundColor(.orange)

            HStack {
                Button("Завтрак") {
                    executionContext.onResolveToWindow("breakfast")
                }
                Button("Обед") {
                    executionContext.onResolveToWindow("lunch")
                }
                Button("Ужин") {
                    executionContext.onResolveToWindow("dinner")
                }
            }
            .buttonStyle(.bordered)
        }
    }
}
