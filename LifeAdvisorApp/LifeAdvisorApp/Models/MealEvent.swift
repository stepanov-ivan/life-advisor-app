import Foundation
import SwiftData

enum MealEventStatus: String, Codable {
    case empty
    case pendingEstimation = "pending-estimation"
    case structured
    case parseFailed = "parse-failed"
    case skipped
}

enum EstimateSourceMode: String, Codable {
    case ingredientBreakdown = "ingredient_breakdown"
    case compositeItem = "composite_item"
}

enum StructureSource: String, Codable {
    case llm
    case memorySuggestion = "memory_suggestion"
    case manualOverride = "manual_override"
}

@Model
final class MealEvent {
    @Attribute(.unique) var id: UUID
    var windowLabel: String
    var timestamp: Date
    var statusRaw: String
    var rawText: String?

    var calories: Double
    var proteins: Double
    var fats: Double
    var carbs: Double

    var confidence: String?
    var sourceModeRaw: String?
    var modelId: String?
    var promptVersion: String?
    var estimationSchemaVersion: String?
    var rawPayload: String?
    var rawPayloadCreatedAt: Date?
    var parseErrorSummary: String?
    var memoryApplied: Bool
    var structureSourceRaw: String
    var outOfSync: Bool
    var userNote: String?

    @Relationship(deleteRule: .cascade, inverse: \EstimateItem.mealEvent)
    var estimateItems: [EstimateItem] = []

    var status: MealEventStatus {
        get { MealEventStatus(rawValue: statusRaw) ?? .empty }
        set { statusRaw = newValue.rawValue }
    }

    var sourceMode: EstimateSourceMode? {
        get {
            guard let sourceModeRaw else { return nil }
            return EstimateSourceMode(rawValue: sourceModeRaw)
        }
        set { sourceModeRaw = newValue?.rawValue }
    }

    var structureSource: StructureSource {
        get { StructureSource(rawValue: structureSourceRaw) ?? .llm }
        set { structureSourceRaw = newValue.rawValue }
    }

    init(
        windowLabel: String,
        timestamp: Date = Date(),
        status: MealEventStatus = .pendingEstimation,
        rawText: String? = nil
    ) {
        self.id = UUID()
        self.windowLabel = windowLabel
        self.timestamp = timestamp
        self.statusRaw = status.rawValue
        self.rawText = rawText
        self.calories = 0
        self.proteins = 0
        self.fats = 0
        self.carbs = 0
        self.memoryApplied = false
        self.structureSourceRaw = StructureSource.llm.rawValue
        self.outOfSync = false
    }

    func applyTotals(calories: Double, proteins: Double, fats: Double, carbs: Double) {
        self.calories = calories
        self.proteins = proteins
        self.fats = fats
        self.carbs = carbs
    }
}
