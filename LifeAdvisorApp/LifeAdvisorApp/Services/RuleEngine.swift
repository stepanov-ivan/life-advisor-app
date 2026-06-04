import Foundation
import SwiftData

@Observable
final class RuleEngine {
    private var rules: [RuleDefinition] = []
    private var modelContext: ModelContext?

    var loadError: String?

    func configure(context: ModelContext) {
        self.modelContext = context
        loadRules()
        syncRuleConfigs()
    }

    // MARK: - Loading

    func loadRules() {
        guard let url = Bundle.main.url(forResource: "nutrition_rules", withExtension: "json") else {
            loadError = "nutrition_rules.json not found in bundle"
            rules = []
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            loadError = "Failed to read nutrition_rules.json"
            rules = []
            return
        }

        guard let file = try? JSONDecoder().decode(RulesFile.self, from: data) else {
            loadError = "Failed to parse nutrition_rules.json"
            rules = []
            return
        }

        // Validate rules
        let validRules = file.rules.filter { rule in
            guard validateRule(rule) else {
                print("[RuleEngine] Skipping invalid rule: \(rule.id)")
                return false
            }
            return true
        }

        rules = validRules
        loadError = nil
    }

    private func validateRule(_ rule: RuleDefinition) -> Bool {
        // type must be range, presence, or countSkipped
        guard ["range", "presence", "countSkipped"].contains(rule.type) else {
            print("[RuleEngine] Rule \(rule.id): unknown type '\(rule.type)'")
            return false
        }

        // window must be day or week
        guard ["day", "week"].contains(rule.window) else {
            print("[RuleEngine] Rule \(rule.id): unknown window '\(rule.window)'")
            return false
        }

        // range rules must have field and at least one bound
        if rule.type == "range" {
            guard rule.field != nil else {
                print("[RuleEngine] Rule \(rule.id): range type requires field")
                return false
            }
            guard rule.params.lower != nil || rule.params.upper != nil else {
                print("[RuleEngine] Rule \(rule.id): range type requires at least one bound")
                return false
            }
        }

        // presence rules must have category
        if rule.type == "presence" {
            guard rule.params.category != nil else {
                print("[RuleEngine] Rule \(rule.id): presence type requires category")
                return false
            }
        }

        return true
    }

    // MARK: - Rule access

    func allRules() -> [RuleDefinition] { rules }

    func enabledRules() -> [RuleDefinition] {
        guard let context = modelContext else { return rules }
        let configs = (try? context.fetch(FetchDescriptor<NutritionRuleConfig>())) ?? []
        let disabledIds = Set(configs.filter { !$0.isEnabled }.map { $0.ruleId })
        return rules.filter { !disabledIds.contains($0.id) }
    }

    func isRuleEnabled(_ ruleId: String) -> Bool {
        guard let context = modelContext else { return true }
        let descriptor = FetchDescriptor<NutritionRuleConfig>(
            predicate: #Predicate { $0.ruleId == ruleId }
        )
        if let config = try? context.fetch(descriptor).first {
            return config.isEnabled
        }
        return true
    }

    func setRuleEnabled(_ ruleId: String, enabled: Bool) {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<NutritionRuleConfig>(
            predicate: #Predicate { $0.ruleId == ruleId }
        )
        if let config = try? context.fetch(descriptor).first {
            config.isEnabled = enabled
        } else {
            context.insert(NutritionRuleConfig(ruleId: ruleId, isEnabled: enabled))
        }
        try? context.save()
    }

    // MARK: - Synchronization

    func syncRuleConfigs() {
        guard let context = modelContext else { return }
        let configs = (try? context.fetch(FetchDescriptor<NutritionRuleConfig>())) ?? []
        let existingIds = Set(configs.map { $0.ruleId })
        let ruleIds = Set(rules.map { $0.id })

        // Create configs for new rules
        for ruleId in ruleIds.subtracting(existingIds) {
            context.insert(NutritionRuleConfig(ruleId: ruleId, isEnabled: true))
        }

        // Delete configs for removed rules
        for config in configs where !ruleIds.contains(config.ruleId) {
            context.delete(config)
        }

        try? context.save()
    }

    // MARK: - Evaluation

    func evaluateToday(rule: RuleDefinition) -> EvaluationResult {
        if rule.window == "week" {
            let recentDay = bestWeekEvaluationDate()
            return evaluateRule(rule, for: recentDay)
        }
        let recentDay = bestEvaluationDate()
        return evaluateRule(rule, for: recentDay)
    }

    func bestEvaluationDate() -> Date {
        mostRecentDayWithData() ?? Date()
    }

    private func mostRecentDayWithData() -> Date? {
        guard let context = modelContext else { return nil }
        let cal = Calendar.current
        for daysBack in 0..<14 {
            guard let date = cal.date(byAdding: .day, value: -daysBack, to: Date()) else { continue }
            let range = DashboardDateLogic.dayRange(for: date)
            let start = range.start
            let end = range.end
            let descriptor = FetchDescriptor<MealEvent>(
                predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end }
            )
            if let events = try? context.fetch(descriptor),
               events.contains(where: { $0.status != .skipped && $0.status != .parseFailed && $0.status != .empty }) {
                return date
            }
        }
        return nil
    }

    func bestWeekEvaluationDate() -> Date {
        guard let context = modelContext else { return Date() }
        let cal = Calendar.current
        for daysBack in 0..<14 {
            guard let date = cal.date(byAdding: .day, value: -daysBack, to: Date()) else { continue }
            let weekDays = weekDayRange(for: date)
            if daysWithStructuredMeals(from: weekDays, context: context) >= 1 {
                return date
            }
        }
        return bestEvaluationDate()
    }

    func evaluateRule(_ rule: RuleDefinition, for date: Date) -> EvaluationResult {
        guard let context = modelContext else { return .noData }

        switch rule.type {
        case "range":
            return evaluateRangeRule(rule, for: date, context: context)
        case "presence":
            return evaluatePresenceRule(rule, for: date, context: context)
        case "countSkipped":
            return evaluateCountSkippedRule(rule, for: date, context: context)
        default:
            return .noData
        }
    }

    private func evaluateRangeRule(_ rule: RuleDefinition, for date: Date, context: ModelContext) -> EvaluationResult {
        guard let field = rule.field else { return .noData }

        let windowDays = rule.window == "week"
            ? weekDayRange(for: date)
            : [date]

        // For day rules, just check if this day has data
        if rule.window == "day" {
            let daysWithData = daysWithStructuredMeals(from: [date], context: context)
            if daysWithData == 0 {
                return .noData
            }
        } else {
            // For week rules, check at least one day has data
            let daysWithData = daysWithStructuredMeals(from: windowDays, context: context)
            if daysWithData == 0 {
                return .noData
            }
        }

        let items = fetchItems(for: windowDays, context: context)

        // Filter out skipped and parseFailed
        let validItems = items.filter { item in
            guard let meal = item.mealEvent else { return false }
            return meal.status != .skipped && meal.status != .parseFailed
        }

        let value = computeField(field, items: validItems, context: context, days: windowDays)
        return evaluateRange(value: value, lower: rule.params.lower, upper: rule.params.upper, warningRatio: rule.warningRatio)
    }

    private func evaluatePresenceRule(_ rule: RuleDefinition, for date: Date, context: ModelContext) -> EvaluationResult {
        guard let category = rule.params.category else { return .noData }

        let dailyItems = fetchItems(for: [date], context: context).filter { item in
            guard let meal = item.mealEvent else { return false }
            return meal.status != .skipped && meal.status != .parseFailed
        }

        let daysWithData = daysWithStructuredMeals(from: [date], context: context)
        if daysWithData == 0 {
            return .noData
        }

        let targetCategories: [String]
        if category == "legume_or_nut" {
            targetCategories = ["legume", "nut_seed"]
        } else {
            targetCategories = [category]
        }

        let inverse = rule.params.inverse ?? false
        return evaluatePresence(dailyItems: dailyItems, targetCategories: targetCategories, inverse: inverse)
    }

    private func evaluateCountSkippedRule(_ rule: RuleDefinition, for date: Date, context: ModelContext) -> EvaluationResult {
        let windowDays = weekDayRange(for: date)

        let daysWithData = daysWithStructuredMeals(from: windowDays, context: context)
        if daysWithData == 0 {
            return .noData
        }

        let warningThreshold = Int(rule.params.warningThreshold ?? 1)
        let violationThreshold = Int(rule.params.violationThreshold ?? 4)

        var skippedCount = 0
        for day in windowDays {
            let range = DashboardDateLogic.dayRange(for: day)
            let start = range.start
            let end = range.end
            let descriptor = FetchDescriptor<MealEvent>(
                predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
                sortBy: [SortDescriptor(\MealEvent.timestamp)]
            )
            let events = (try? context.fetch(descriptor)) ?? []
            if events.contains(where: { $0.status == .skipped }) {
                skippedCount += 1
            }
        }

        return evaluateCountSkipped(skippedCount: skippedCount, warningThreshold: warningThreshold, violationThreshold: violationThreshold)
    }

    // MARK: - Field computation

    private func computeField(_ field: String, items: [EstimateItem], context: ModelContext, days: [Date]) -> Double {
        switch field {
        case "fatPercent":
            let totals = aggregateTotals(items: items, days: days, context: context)
            guard totals.calories > 0 else { return 0 }
            return (totals.fats * 9) / totals.calories
        case "proteinPercent":
            let totals = aggregateTotals(items: items, days: days, context: context)
            guard totals.calories > 0 else { return 0 }
            return (totals.proteins * 4) / totals.calories
        case "saturatedFatPercent":
            let totals = aggregateTotals(items: items, days: days, context: context)
            guard totals.calories > 0 else { return 0 }
            return (totals.saturatedFats * 9) / totals.calories
        case "transFatPercent":
            return 0 // No dedicated field yet, shows no data
        case "pufaPercent":
            return 0 // No dedicated field yet, shows no data
        case "carbsPercent":
            let totals = aggregateTotals(items: items, days: days, context: context)
            guard totals.calories > 0 else { return 0 }
            return (totals.carbs * 4) / totals.calories
        case "sugarPercent":
            let totals = aggregateTotals(items: items, days: days, context: context)
            guard totals.calories > 0 else { return 0 }
            return (totals.sugar * 4) / totals.calories
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
            let totals = aggregateTotals(items: items, days: days, context: context)
            let target = UserDefaults.standard.double(forKey: "daily_calorie_target")
            guard target > 0, totals.calories > 0 else { return 0 }
            return (totals.calories - target) / target
        default:
            return 0
        }
    }

    private struct DayTotals {
        var calories: Double = 0
        var proteins: Double = 0
        var fats: Double = 0
        var carbs: Double = 0
        var saturatedFats: Double = 0
        var sugar: Double = 0
    }

    private func aggregateTotals(items: [EstimateItem], days: [Date], context: ModelContext) -> DayTotals {
        var totals = DayTotals()
        totals.calories = items.reduce(0) { $0 + $1.estimatedCalories }
        totals.proteins = items.reduce(0) { $0 + $1.estimatedProteins }
        totals.fats = items.reduce(0) { $0 + $1.estimatedFats }
        totals.carbs = items.reduce(0) { $0 + $1.estimatedCarbs }
        totals.saturatedFats = items.reduce(0) { $0 + $1.estimatedSaturatedFats }
        totals.sugar = items.reduce(0) { $0 + $1.estimatedSugar }
        return totals
    }

    // MARK: - Helpers

    private func fetchItems(for days: [Date], context: ModelContext) -> [EstimateItem] {
        var allItems: [EstimateItem] = []
        for day in days {
            let range = DashboardDateLogic.dayRange(for: day)
            let start = range.start
            let end = range.end
            let descriptor = FetchDescriptor<MealEvent>(
                predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end }
            )
            if let events = try? context.fetch(descriptor) {
                for event in events {
                    allItems.append(contentsOf: event.estimateItems)
                }
            }
        }
        return allItems
    }

    private func daysWithStructuredMeals(from days: [Date], context: ModelContext) -> Int {
        var count = 0
        for day in days {
            let range = DashboardDateLogic.dayRange(for: day)
            let start = range.start
            let end = range.end
            let descriptor = FetchDescriptor<MealEvent>(
                predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end }
            )
            if let events = try? context.fetch(descriptor) {
                let hasStructured = events.contains { event in
                    event.status != .skipped && event.status != .parseFailed && event.status != .empty
                }
                if hasStructured { count += 1 }
            }
        }
        return count
    }

    private func weekDayRange(for date: Date) -> [Date] {
        DashboardDateLogic.weekDates(around: date)
    }

    // MARK: - Violation management

    func violationsForMeal(_ meal: MealEvent) -> [RuleViolation] {
        guard let context = modelContext else { return [] }
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: meal.timestamp)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        let descriptor = FetchDescriptor<RuleViolation>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        let dayViolations = (try? context.fetch(descriptor)) ?? []

        let mealItemIds = Set(meal.estimateItems.map { $0.persistentModelID.storeIdentifier ?? "" })

        return dayViolations.filter { violation in
            // Check contributionJSON for matching itemIds
            if let json = violation.contributionJSON,
               let data = json.data(using: .utf8),
               let entries = try? JSONDecoder().decode([ContributionEntry].self, from: data) {
                let contributionItemIds = Set(entries.map { $0.itemId })
                if !contributionItemIds.isDisjoint(with: mealItemIds) {
                    return true
                }
            }
            // Fallback: direct mealEvent match
            if violation.mealEvent?.persistentModelID == meal.persistentModelID {
                return true
            }
            return false
        }
    }

    func violationsForDay(_ date: Date) -> [RuleViolation] {
        guard let context = modelContext else { return [] }
        let range = DashboardDateLogic.dayRange(for: date)
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<RuleViolation>(
            predicate: #Predicate { $0.date >= start && $0.date < end }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func generateViolations(for date: Date) {
        guard let context = modelContext else { return }
        let dayRange = DashboardDateLogic.dayRange(for: date)
        let ds = dayRange.start
        let de = dayRange.end

        // Remove old violations for this day
        let oldDescriptor = FetchDescriptor<RuleViolation>(
            predicate: #Predicate { $0.date >= ds && $0.date < de }
        )
        if let oldViolations = try? context.fetch(oldDescriptor) {
            for v in oldViolations { context.delete(v) }
        }

        // Evaluate all enabled rules for this day
        for rule in enabledRules() {
            let result = evaluateRule(rule, for: date)
            if result.zone == .warning || result.zone == .violation {
                // Compute contribution map
                let contributions = contributionMap(for: rule, date: date)
                let contribJSON = encodeContributionJSON(contributions)

                // Find the culprit meal/event/item
                let events = eventsForDay(date, context: context)
                let culpritEvent = findCulpritEvent(rule: rule, events: events, context: context)

                let violation = RuleViolation(
                    ruleId: rule.id,
                    date: date,
                    zone: result.zone.rawValue,
                    magnitude: result.magnitude,
                    reasonCode: result.reasonCode,
                    contributionJSON: contribJSON,
                    mealEvent: culpritEvent.meal,
                    estimateItem: culpritEvent.item
                )
                context.insert(violation)
            }
        }

        try? context.save()
    }

    func fullRebuild(for date: Date) {
        guard let context = modelContext else { return }
        let windowDays = weekDayRange(for: date)

        // Remove all violations for the week
        for day in windowDays {
            let range = DashboardDateLogic.dayRange(for: day)
            let start = range.start
            let end = range.end
            let descriptor = FetchDescriptor<RuleViolation>(
                predicate: #Predicate { $0.date >= start && $0.date < end }
            )
            if let violations = try? context.fetch(descriptor) {
                for v in violations { context.delete(v) }
            }
        }

        // Regenerate for each day
        for day in windowDays {
            generateViolations(for: day)
        }
    }

    func resetWeekIfNeeded() {
        // Remove violations older than current week
        guard let context = modelContext else { return }
        let today = Date()
        let weekStart = weekDayRange(for: today).first ?? today
        let startOfWeek = Calendar.current.startOfDay(for: weekStart)
        let descriptor = FetchDescriptor<RuleViolation>(
            predicate: #Predicate { $0.date < startOfWeek }
        )
        if let old = try? context.fetch(descriptor) {
            for v in old { context.delete(v) }
        }
        try? context.save()
    }

    func ruleViolationsForWeek(ruleId: String, weekStart: Date) -> [RuleViolation] {
        guard let context = modelContext else { return [] }
        let endOfWeek = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
        let descriptor = FetchDescriptor<RuleViolation>(
            predicate: #Predicate { $0.ruleId == ruleId && $0.date >= weekStart && $0.date < endOfWeek },
            sortBy: [SortDescriptor(\RuleViolation.date, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Contribution analysis

    struct ContributionEntry: Codable {
        let itemId: String
        let name: String
        let percent: Double
    }

    func contributionMap(for rule: RuleDefinition, date: Date) -> [ContributionEntry] {
        guard let context = modelContext else { return [] }

        switch rule.type {
        case "range":
            return contributionForRangeRule(rule, date: date, context: context)
        case "presence":
            return contributionForPresenceRule(rule, date: date, context: context)
        default:
            return []
        }
    }

    private func contributionForRangeRule(_ rule: RuleDefinition, date: Date, context: ModelContext) -> [ContributionEntry] {
        guard let field = rule.field else { return [] }
        let windowDays = rule.window == "week" ? weekDayRange(for: date) : [date]
        let items = fetchItems(for: windowDays, context: context)
            .filter { item in
                guard let meal = item.mealEvent else { return false }
                return meal.status != .skipped && meal.status != .parseFailed
            }

        guard !items.isEmpty else { return [] }

        // Для percent-полей продукт сам должен быть значимым источником нутриента
        let percentFields: Set<String> = ["fatPercent", "saturatedFatPercent", "transFatPercent", "proteinPercent", "carbsPercent", "sugarPercent"]
        let significantItems: Set<ObjectIdentifier>? = {
            guard percentFields.contains(field), let upper = rule.params.upper else { return nil }
            let sig = items.filter { item in
                let itemValue = itemValueForField(field, item: item)
                let result = evaluateRange(value: itemValue, lower: nil, upper: upper, warningRatio: rule.warningRatio)
                return result.zone != .normal
            }
            return Set(sig.map { ObjectIdentifier($0) })
        }()

        let entries: [ContributionEntry]
        switch field {
        case "fatPercent", "saturatedFatPercent", "transFatPercent":
            let totalNutrient = items.reduce(0) { $0 + $1.estimatedFats }
            guard totalNutrient > 0 else { return [] }
            entries = items.compactMap { item in
                guard significantItems?.contains(ObjectIdentifier(item)) ?? true else { return nil }
                return ContributionEntry(
                    itemId: item.persistentModelID.storeIdentifier ?? "",
                    name: item.name,
                    percent: (item.estimatedFats / totalNutrient) * 100
                )
            }
        case "proteinPercent":
            let totalNutrient = items.reduce(0) { $0 + $1.estimatedProteins }
            guard totalNutrient > 0 else { return [] }
            entries = items.compactMap { item in
                guard significantItems?.contains(ObjectIdentifier(item)) ?? true else { return nil }
                return ContributionEntry(
                    itemId: item.persistentModelID.storeIdentifier ?? "",
                    name: item.name,
                    percent: (item.estimatedProteins / totalNutrient) * 100
                )
            }
        case "carbsPercent":
            let totalNutrient = items.reduce(0) { $0 + $1.estimatedCarbs }
            guard totalNutrient > 0 else { return [] }
            entries = items.compactMap { item in
                guard significantItems?.contains(ObjectIdentifier(item)) ?? true else { return nil }
                return ContributionEntry(
                    itemId: item.persistentModelID.storeIdentifier ?? "",
                    name: item.name,
                    percent: (item.estimatedCarbs / totalNutrient) * 100
                )
            }
        case "sugarPercent":
            let totalNutrient = items.reduce(0) { $0 + $1.estimatedSugar }
            guard totalNutrient > 0 else { return [] }
            entries = items.compactMap { item in
                guard significantItems?.contains(ObjectIdentifier(item)) ?? true else { return nil }
                return ContributionEntry(
                    itemId: item.persistentModelID.storeIdentifier ?? "",
                    name: item.name,
                    percent: (item.estimatedSugar / totalNutrient) * 100
                )
            }
        case "sodiumMg":
            let totalValue = items.reduce(0) { $0 + $1.estimatedSodium }
            guard totalValue > 0 else { return [] }
            entries = items.map { item in
                ContributionEntry(
                    itemId: item.persistentModelID.storeIdentifier ?? "",
                    name: item.name,
                    percent: (item.estimatedSodium / totalValue) * 100
                )
            }
        case "fiberGrams":
            let totalValue = items.reduce(0) { $0 + $1.estimatedFiber }
            guard totalValue > 0 else { return [] }
            entries = items.map { item in
                ContributionEntry(
                    itemId: item.persistentModelID.storeIdentifier ?? "",
                    name: item.name,
                    percent: (item.estimatedFiber / totalValue) * 100
                )
            }
        case "fruitVegGrams":
            let totalValue = items
                .filter { $0.foodCategory == "fruit" || $0.foodCategory == "vegetable" }
                .reduce(0) { $0 + $1.grams }
            guard totalValue > 0 else { return [] }
            entries = items
                .filter { $0.foodCategory == "fruit" || $0.foodCategory == "vegetable" }
                .map { item in
                    ContributionEntry(
                        itemId: item.persistentModelID.storeIdentifier ?? "",
                        name: item.name,
                        percent: (item.grams / totalValue) * 100
                    )
                }
        case "redMeatGrams":
            let totalValue = items
                .filter { $0.foodCategory == "red_meat" }
                .reduce(0) { $0 + $1.grams }
            guard totalValue > 0 else { return [] }
            entries = items
                .filter { $0.foodCategory == "red_meat" }
                .map { item in
                    ContributionEntry(
                        itemId: item.persistentModelID.storeIdentifier ?? "",
                        name: item.name,
                        percent: (item.grams / totalValue) * 100
                    )
                }
        case "energyBalancePercent":
            let totalCalories = items.reduce(0) { $0 + $1.estimatedCalories }
            guard totalCalories > 0 else { return [] }
            entries = items.map { item in
                ContributionEntry(
                    itemId: item.persistentModelID.storeIdentifier ?? "",
                    name: item.name,
                    percent: (item.estimatedCalories / totalCalories) * 100
                )
            }
        default:
            return []
        }

        return entries
            .filter { $0.percent > 33 }
            .sorted { $0.percent > $1.percent }
            .prefix(3)
            .map { $0 }
    }

    private func contributionForPresenceRule(_ rule: RuleDefinition, date: Date, context: ModelContext) -> [ContributionEntry] {
        // category_missing: не подсвечиваем продукты — это нарушение дня, а не продукта
        let inverse = rule.params.inverse ?? false
        guard inverse else { return [] }

        guard let category = rule.params.category else { return [] }
        let items = fetchItems(for: [date], context: context)
            .filter { item in
                guard let meal = item.mealEvent else { return false }
                return meal.status != .skipped && meal.status != .parseFailed
            }

        let targetCategories = category == "legume_or_nut" ? ["legume", "nut_seed"] : [category]

        return items.compactMap { item in
            let match = targetCategories.contains(item.foodCategory ?? "")
            guard match else { return nil }
            return ContributionEntry(
                itemId: item.persistentModelID.storeIdentifier ?? "",
                name: item.name,
                percent: 100
            )
        }
        .sorted { $0.percent > $1.percent }
        .prefix(3)
        .map { $0 }
    }

    private func encodeContributionJSON(_ entries: [ContributionEntry]) -> String? {
        guard !entries.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(entries),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }

    // MARK: - Culprit tracing

    private struct CulpritResult {
        let meal: MealEvent?
        let item: EstimateItem?
    }

    private func findCulpritEvent(rule: RuleDefinition, events: [MealEvent], context: ModelContext) -> CulpritResult {
        for event in events {
            guard event.status != .skipped, event.status != .parseFailed else { continue }
            for item in event.estimateItems {
                if isItemViolating(item: item, rule: rule) {
                    return CulpritResult(meal: event, item: item)
                }
            }
        }
        // No specific culprit - violation is at the day level
        return CulpritResult(meal: nil, item: nil)
    }

    private func isItemViolating(item: EstimateItem, rule: RuleDefinition) -> Bool {
        switch rule.type {
        case "presence":
            guard let category = rule.params.category else { return false }
            let targetCategories = category == "legume_or_nut" ? ["legume", "nut_seed"] : [category]
            let match = targetCategories.contains(item.foodCategory ?? "")
            let inverse = rule.params.inverse ?? false
            return inverse ? match : !match
        case "range":
            guard let field = rule.field else { return false }
            let value = itemValueForField(field, item: item)
            let result = evaluateRange(value: value, lower: rule.params.lower, upper: rule.params.upper, warningRatio: rule.warningRatio)
            return result.zone == .violation || result.zone == .warning
        default:
            return false
        }
    }

    private func itemValueForField(_ field: String, item: EstimateItem) -> Double {
        switch field {
        case "fatPercent":
            guard item.estimatedCalories > 0 else { return 0 }
            return (item.estimatedFats * 9) / item.estimatedCalories
        case "saturatedFatPercent":
            guard item.estimatedCalories > 0 else { return 0 }
            return (item.estimatedSaturatedFats * 9) / item.estimatedCalories
        case "proteinPercent":
            guard item.estimatedCalories > 0 else { return 0 }
            return (item.estimatedProteins * 4) / item.estimatedCalories
        case "carbsPercent":
            guard item.estimatedCalories > 0 else { return 0 }
            return (item.estimatedCarbs * 4) / item.estimatedCalories
        case "sugarPercent":
            guard item.estimatedCalories > 0 else { return 0 }
            return (item.estimatedSugar * 4) / item.estimatedCalories
        case "energyBalancePercent":
            return item.estimatedCalories
        case "sodiumMg":
            return item.estimatedSodium
        case "fiberGrams":
            return item.estimatedFiber
        case "redMeatGrams":
            return item.foodCategory == "red_meat" ? item.grams : 0
        default:
            return 0
        }
    }

    private func eventsForDay(_ date: Date, context: ModelContext) -> [MealEvent] {
        let range = DashboardDateLogic.dayRange(for: date)
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<MealEvent>(
            predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end },
            sortBy: [SortDescriptor(\MealEvent.timestamp)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Metric formatting

    struct RuleMetricDisplay {
        let valueFormatted: String
        let thresholdFormatted: String
        let unit: String
        let zone: RuleZone
    }

    func formattedMetric(for rule: RuleDefinition, date: Date) -> RuleMetricDisplay {
        let result = evaluateRule(rule, for: date)
        let format = metricFormat(for: rule.field)

        switch rule.type {
        case "range":
            let rawValue = computeMetricValue(field: rule.field, rule: rule, date: date)
            let displayValue = rawValue * format.multiply
            let decimals = format.decimals
            let valueStr = String(format: "%.\(decimals)f", displayValue)

            let thresholdStr: String
            switch (rule.params.lower, rule.params.upper) {
            case let (lo?, up?):
                let loStr = String(format: "%.\(decimals)f", lo * format.multiply)
                let upStr = String(format: "%.\(decimals)f", up * format.multiply)
                thresholdStr = "\(loStr)–\(upStr)\(format.unit)"
            case let (lo?, nil):
                let loStr = String(format: "%.\(decimals)f", lo * format.multiply)
                thresholdStr = "≥\(loStr)\(format.unit)"
            case let (nil, up?):
                let upStr = String(format: "%.\(decimals)f", up * format.multiply)
                thresholdStr = "≤\(upStr)\(format.unit)"
            case (nil, nil):
                thresholdStr = ""
            }

            return RuleMetricDisplay(
                valueFormatted: valueStr + format.unit,
                thresholdFormatted: thresholdStr,
                unit: format.unit,
                zone: result.zone
            )

        case "presence":
            let labelKey: String
            switch result.zone {
            case .normal: labelKey = "zone_normal"
            case .warning: labelKey = "zone_warning"
            case .violation: labelKey = "zone_violation"
            case .noData: labelKey = "zone_no_data"
            }
            let label = LocalizationHelper.localized(labelKey, table: "Rules")
            return RuleMetricDisplay(
                valueFormatted: label,
                thresholdFormatted: "",
                unit: "",
                zone: result.zone
            )

        case "countSkipped":
            let skippedCount = computeSkippedCount(for: date)
            let violationThreshold = Int(rule.params.violationThreshold ?? 4)
            let skipsLabel = LocalizationHelper.localized("skips_format", table: "Rules")
            return RuleMetricDisplay(
                valueFormatted: String(format: skipsLabel, skippedCount),
                thresholdFormatted: "≤\(violationThreshold)",
                unit: "",
                zone: result.zone
            )

        default:
            return RuleMetricDisplay(
                valueFormatted: "—",
                thresholdFormatted: "",
                unit: "",
                zone: .noData
            )
        }
    }

    private struct MetricFormat {
        let unit: String
        let multiply: Double
        let decimals: Int
    }

    private func metricFormat(for field: String?) -> MetricFormat {
        guard let field else {
            return MetricFormat(unit: "", multiply: 1, decimals: 0)
        }
        switch field {
        case "fatPercent", "proteinPercent", "carbsPercent",
             "saturatedFatPercent", "transFatPercent", "sugarPercent",
             "energyBalancePercent", "pufaPercent":
            return MetricFormat(unit: "%", multiply: 100, decimals: 1)
        case "sodiumMg":
            return MetricFormat(unit: " мг", multiply: 1, decimals: 0)
        case "fiberGrams", "fruitVegGrams", "redMeatGrams":
            return MetricFormat(unit: " г", multiply: 1, decimals: 0)
        default:
            return MetricFormat(unit: "", multiply: 1, decimals: 0)
        }
    }

    private func computeMetricValue(field: String?, rule: RuleDefinition, date: Date) -> Double {
        guard let field, let context = modelContext else { return 0 }
        let windowDays = rule.window == "week" ? weekDayRange(for: date) : [date]
        let items = fetchItems(for: windowDays, context: context)
            .filter { item in
                guard let meal = item.mealEvent else { return false }
                return meal.status != .skipped && meal.status != .parseFailed
            }
        return computeField(field, items: items, context: context, days: windowDays)
    }

    private func computeSkippedCount(for date: Date) -> Int {
        guard let context = modelContext else { return 0 }
        let windowDays = weekDayRange(for: date)
        var skippedCount = 0
        for day in windowDays {
            let range = DashboardDateLogic.dayRange(for: day)
            let start = range.start
            let end = range.end
            let descriptor = FetchDescriptor<MealEvent>(
                predicate: #Predicate { $0.timestamp >= start && $0.timestamp < end }
            )
            let events = (try? context.fetch(descriptor)) ?? []
            if events.contains(where: { $0.status == .skipped }) {
                skippedCount += 1
            }
        }
        return skippedCount
    }

    // MARK: - Violation descriptions

    func violationDescription(for violation: RuleViolation) -> String {
        let localizer = RulePresentationLocalizer(language: AppLanguageManager.currentEffectiveLanguage)
        return localizer.localizedDescription(for: violation, engine: self)
    }

    // MARK: - Summary

    func summary(date: Date) -> (normal: Int, total: Int) {
        let enabled = enabledRules()
        var normalCount = 0
        for rule in enabled {
            let result = evaluateToday(rule: rule)
            if result.zone == .normal { normalCount += 1 }
        }
        return (normalCount, enabled.count)
    }

}
