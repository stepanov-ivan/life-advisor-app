import Foundation
import SwiftData

enum EstimationRuntime {
    static func applySuggestionPrior(
        totals: LLMClient.Totals,
        suggestion: MemorySuggestion?
    ) -> (calories: Double, proteins: Double, fats: Double, carbs: Double) {
        guard let suggestion else {
            return (totals.calories, totals.proteins, totals.fats, totals.carbs)
        }
        return (
            calories: (totals.calories + suggestion.calories) / 2,
            proteins: (totals.proteins + suggestion.proteins) / 2,
            fats: (totals.fats + suggestion.fats) / 2,
            carbs: (totals.carbs + suggestion.carbs) / 2
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
                sourceMode: mode == "ingredient_breakdown" ? .ingredientBreakdown : .compositeItem,
                quantity: parsed.quantity,
                unit: parsed.unit
            )
            estimateItem.mealEvent = event
            modelContext.insert(estimateItem)
        }
    }

    static func lowConfidenceWarningVisible(_ confidence: String?) -> Bool {
        confidence == "low"
    }

    static func shouldUpdatePrimarySuggestion(oldCalories: Double, newCalories: Double) -> Bool {
        guard oldCalories > 0 else { return true }
        return abs(newCalories - oldCalories) / oldCalories <= 0.30
    }
}
