import Foundation
import SwiftData

struct MealPlanningContext {
    let selectedDate: Date
    let dayEvents: [MealEvent]
    let windows: [MealWindow]
}

enum MealScenarioClassifier {
    static func classify(_ message: String, context: MealPlanningContext) async -> MealScenarioClassification {
        if LLMClient.isConfigured,
           let llmResult = try? await LLMClient.classifyMealScenario(
                message: message,
                selectedDate: context.selectedDate,
                dayEvents: context.dayEvents
           ) {
            return llmResult
        }

        let lowered = message.lowercased()
        let scenario: MealScenario
        if lowered.contains("убери") || lowered.contains("добавь к") || lowered.contains("исправ") || lowered.contains("редакт") {
            scenario = .edit
        } else {
            scenario = .create
        }
        return MealScenarioClassification(scenario: scenario, resolvedDay: resolveDay(in: lowered, selectedDate: context.selectedDate))
    }

    private static func resolveDay(in text: String, selectedDate: Date) -> Date {
        let calendar = Calendar.current
        if text.contains("вчера") {
            return DashboardDateLogic.startOfDay(calendar.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate)
        }
        if text.contains("завтра") {
            return DashboardDateLogic.startOfDay(calendar.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate)
        }
        return DashboardDateLogic.startOfDay(selectedDate)
    }
}

enum MealStepPlanner {
    static func plan(
        message: String,
        classification: MealScenarioClassification,
        context: MealPlanningContext
    ) async throws -> MealExecutionSession {
        if LLMClient.isConfigured, let llmPlan = try? await LLMClient.planMealExecution(
            message: message,
            scenario: classification.scenario,
            selectedDate: classification.resolvedDay,
            windows: context.windows,
            dayEvents: context.dayEvents
        ) {
            return llmPlan
        }

        let fallbackSteps = fallbackPlan(
            message: message,
            scenario: classification.scenario,
            day: classification.resolvedDay,
            windows: context.windows
        )
        return MealExecutionSession(
            scenario: classification.scenario,
            originalMessage: message,
            steps: fallbackSteps
        )
    }

    private static func fallbackPlan(
        message: String,
        scenario: MealScenario,
        day: Date,
        windows: [MealWindow]
    ) -> [MealExecutionStep] {
        let segments = extractDaySegments(from: message, baseDay: day)
        return segments.flatMap { segmentDay, segmentText in
            let normalized = segmentText
                .replacingOccurrences(of: "\n", with: ",")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let targetWindows: [MealWindow]
            if segmentText.lowercased().contains("завтрак") || segmentText.lowercased().contains("обед") || segmentText.lowercased().contains("ужин") {
                targetWindows = windows.filter { window in
                    let lowered = segmentText.lowercased()
                    if lowered.contains("завтрак"), window.windowId == "breakfast" { return true }
                    if lowered.contains("обед"), window.windowId == "lunch" { return true }
                    if lowered.contains("ужин"), window.windowId == "dinner" { return true }
                    return false
                }
            } else {
                let inferredCount = inferredWindowCount(for: normalized.count, scenario: scenario)
                targetWindows = Array(windows.prefix(inferredCount))
            }

            let chunks = distributeProducts(normalized, into: max(1, targetWindows.count))
            return targetWindows.enumerated().map { index, window in
                let products = chunks[safe: index] ?? []
                return MealExecutionStep(
                    type: scenario == .create ? .create : .edit,
                    day: segmentDay,
                    windowId: window.windowId,
                    title: window.localizedName(),
                    products: products.map { productName in
                        MealProductDraft(
                            name: productName,
                            grams: 100,
                            estimatedCalories: 120,
                            estimatedProteins: 5,
                            estimatedFats: 4,
                            estimatedCarbs: 15,
                            reason: "Черновик из свободного ввода"
                        )
                    },
                    sourceText: products.joined(separator: ", "),
                    state: .readyForConfirm
                )
            }
        }
    }

    private static func distributeProducts(_ products: [String], into bucketCount: Int) -> [[String]] {
        guard bucketCount > 0 else { return [] }
        if bucketCount == 1 { return [products] }

        var buckets = Array(repeating: [String](), count: bucketCount)
        for (index, product) in products.enumerated() {
            let bucketIndex: Int
            if bucketCount == 3 {
                if index < 2 {
                    bucketIndex = 0
                } else if index < 4 {
                    bucketIndex = 1
                } else {
                    bucketIndex = 2
                }
            } else {
                bucketIndex = min(bucketCount - 1, index)
            }
            buckets[bucketIndex].append(product)
        }
        return buckets
    }

    private static func inferredWindowCount(for productCount: Int, scenario: MealScenario) -> Int {
        guard productCount > 0 else { return 0 }
        if scenario == .edit {
            return 1
        }
        switch productCount {
        case 1:
            return 1
        case 2...4:
            return 2
        default:
            return 3
        }
    }

    private static func extractDaySegments(from message: String, baseDay: Date) -> [(Date, String)] {
        let lowered = message.lowercased()
        let calendar = Calendar.current
        let markers: [(String, Int)] = [("вчера", -1), ("сегодня", 0), ("завтра", 1)]
        let found = markers.compactMap { marker, offset -> (Range<String.Index>, Int)? in
            guard let range = lowered.range(of: marker) else { return nil }
            return (range, offset)
        }.sorted { $0.0.lowerBound < $1.0.lowerBound }

        guard !found.isEmpty else {
            return [(DashboardDateLogic.startOfDay(baseDay), message)]
        }

        var segments: [(Date, String)] = []
        for (index, foundMarker) in found.enumerated() {
            let start = foundMarker.0.upperBound
            let end = index + 1 < found.count ? found[index + 1].0.lowerBound : message.endIndex
            let text = String(message[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let day = DashboardDateLogic.startOfDay(calendar.date(byAdding: .day, value: foundMarker.1, to: baseDay) ?? baseDay)
            if !text.isEmpty {
                segments.append((day, text))
            }
        }
        return segments.isEmpty ? [(DashboardDateLogic.startOfDay(baseDay), message)] : segments
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
