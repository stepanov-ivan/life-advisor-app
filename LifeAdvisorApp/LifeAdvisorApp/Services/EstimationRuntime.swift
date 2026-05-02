import Foundation
import SwiftData

enum EstimationRuntime {
    static func applyMemoryPrior(
        totals: LLMClient.Totals,
        memory: EstimationMemory?
    ) -> (calories: Double, proteins: Double, fats: Double, carbs: Double) {
        guard let memory else {
            return (totals.calories, totals.proteins, totals.fats, totals.carbs)
        }
        return (
            calories: (totals.calories + memory.calories) / 2,
            proteins: (totals.proteins + memory.proteins) / 2,
            fats: (totals.fats + memory.fats) / 2,
            carbs: (totals.carbs + memory.carbs) / 2
        )
    }

    static func aggregateTotals(items: [EstimateItem]) -> (calories: Double, proteins: Double, fats: Double, carbs: Double) {
        items.reduce(into: (0.0, 0.0, 0.0, 0.0)) { acc, item in
            acc.0 += item.estimatedCalories
            acc.1 += item.estimatedProteins
            acc.2 += item.estimatedFats
            acc.3 += item.estimatedCarbs
        }
    }

    @MainActor
    static func overwriteSnapshot(
        event: MealEvent,
        with parsedItems: [LLMClient.EstimateItemResult],
        mode: String,
        modelContext: ModelContext
    ) {
        let oldItems = event.estimateItems
        for oldItem in oldItems { modelContext.delete(oldItem) }

        for parsed in parsedItems {
            let estimateItem = EstimateItem(
                name: parsed.name,
                estimatedCalories: parsed.estimatedCalories,
                estimatedProteins: parsed.estimatedProteins,
                estimatedFats: parsed.estimatedFats,
                estimatedCarbs: parsed.estimatedCarbs,
                impactScore: parsed.clampedImpactScore,
                reason: parsed.reason,
                highCalorieFlag: parsed.highCalorieFlag,
                sourceMode: mode == "ingredient_breakdown" ? .ingredientBreakdown : .compositeItem
            )
            estimateItem.mealEvent = event
            modelContext.insert(estimateItem)
        }
    }

    static func lowConfidenceWarningVisible(_ confidence: String?) -> Bool {
        confidence == "low"
    }
}
