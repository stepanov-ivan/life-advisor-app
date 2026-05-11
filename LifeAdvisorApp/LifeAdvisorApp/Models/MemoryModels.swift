import Foundation
import SwiftData

enum HypothesisStatus: String, Codable {
    case pendingConfirmation = "pending_confirmation"
    case confirmed
    case rejected
    case underReview = "under_review"
}

@Model
final class MemorySuggestion {
    @Attribute(.unique) var id: UUID
    var canonicalKey: String
    var displayText: String
    var calories: Double
    var proteins: Double
    var fats: Double
    var carbs: Double
    var usageCount: Int
    var lastUsedAt: Date
    var version: Int
    var isFallback: Bool
    var isCandidate: Bool
    var candidateCount: Int

    @Relationship(deleteRule: .cascade, inverse: \MemorySuggestionAlias.suggestion)
    var aliases: [MemorySuggestionAlias] = []

    init(
        canonicalKey: String,
        displayText: String,
        calories: Double,
        proteins: Double,
        fats: Double,
        carbs: Double,
        usageCount: Int = 0,
        lastUsedAt: Date = Date(),
        version: Int = 1,
        isFallback: Bool = false,
        isCandidate: Bool = false,
        candidateCount: Int = 0
    ) {
        self.id = UUID()
        self.canonicalKey = canonicalKey
        self.displayText = displayText
        self.calories = calories
        self.proteins = proteins
        self.fats = fats
        self.carbs = carbs
        self.usageCount = usageCount
        self.lastUsedAt = lastUsedAt
        self.version = version
        self.isFallback = isFallback
        self.isCandidate = isCandidate
        self.candidateCount = candidateCount
    }
}

@Model
final class MemorySuggestionAlias {
    @Attribute(.unique) var text: String
    var suggestion: MemorySuggestion?

    init(text: String, suggestion: MemorySuggestion? = nil) {
        self.text = text
        self.suggestion = suggestion
    }
}

@Model
final class MemoryHypothesis {
    @Attribute(.unique) var key: String
    var title: String
    var score: Double
    var signalCount: Int
    var statusRaw: String
    var nextPromptAt: Date?
    var lastSeenAt: Date
    var confirmedAt: Date?
    var lastConflictAt: Date?
    var cooldownUntil: Date?

    var status: HypothesisStatus {
        get { HypothesisStatus(rawValue: statusRaw) ?? .pendingConfirmation }
        set { statusRaw = newValue.rawValue }
    }

    init(
        key: String,
        title: String,
        score: Double = 0.5,
        signalCount: Int = 0,
        status: HypothesisStatus = .pendingConfirmation,
        nextPromptAt: Date? = nil,
        lastSeenAt: Date = Date()
    ) {
        self.key = key
        self.title = title
        self.score = score
        self.signalCount = signalCount
        self.statusRaw = status.rawValue
        self.nextPromptAt = nextPromptAt
        self.lastSeenAt = lastSeenAt
    }
}

@Model
final class MemoryDataGap {
    @Attribute(.unique) var key: String
    var title: String
    var itemFingerprint: String
    var resolved: Bool
    var confirmationCount: Int
    var createdAt: Date
    var updatedAt: Date
    var resolvedAt: Date?

    init(
        key: String,
        title: String,
        itemFingerprint: String,
        resolved: Bool = false,
        confirmationCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.key = key
        self.title = title
        self.itemFingerprint = itemFingerprint
        self.resolved = resolved
        self.confirmationCount = confirmationCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
