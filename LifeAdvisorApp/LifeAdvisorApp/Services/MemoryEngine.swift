import Foundation
import SwiftData

enum MemoryEngine {
    private static let day: TimeInterval = 24 * 60 * 60

    struct SuggestionViewModel {
        let canonicalKey: String
        let text: String
        let calories: Double
        let proteins: Double
        let fats: Double
        let carbs: Double
        let source: StructureSource
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "[^a-zа-я0-9\\s]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .sorted()
            .joined(separator: " ")
    }

    static func isOutOfSync(selectedText: String?, currentText: String) -> Bool {
        guard let selectedText else { return false }
        return normalize(selectedText) != normalize(currentText)
    }

    static func topSuggestions(
        query: String,
        from events: [MealEvent],
        suggestions: [MemorySuggestion],
        limit: Int = 5
    ) -> [SuggestionViewModel] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        var grouped: [String: (count: Int, lastSeen: Date, text: String, totals: (Double, Double, Double, Double), source: StructureSource)] = [:]

        for suggestion in suggestions where !suggestion.isCandidate {
            let canonicalMatch = suggestion.displayText.lowercased().contains(normalizedQuery) || suggestion.canonicalKey.contains(normalize(normalizedQuery))
            let aliasMatch = suggestion.aliases.contains(where: { $0.text.lowercased().contains(normalizedQuery) || normalize($0.text).contains(normalize(normalizedQuery)) })
            guard canonicalMatch || aliasMatch else { continue }
            grouped[suggestion.canonicalKey] = (
                suggestion.usageCount,
                suggestion.lastUsedAt,
                suggestion.displayText,
                (suggestion.calories, suggestion.proteins, suggestion.fats, suggestion.carbs),
                .memorySuggestion
            )
        }

        let candidates = events
            .filter { $0.status == .structured }
            .prefix(50)
            .compactMap { event -> (MealEvent, String)? in
                guard let text = event.rawText, !text.isEmpty else { return nil }
                return (event, text)
            }

        for (event, text) in candidates {
            let key = normalize(text)
            guard !key.isEmpty else { continue }
            let current = grouped[key]
            let newCount = (current?.count ?? 0) + 1
            let lastSeen = max(current?.lastSeen ?? .distantPast, event.timestamp)
            grouped[key] = (
                newCount,
                lastSeen,
                text,
                (event.calories, event.proteins, event.fats, event.carbs),
                current?.source ?? event.structureSource
            )
        }

        let normalizedForSimilarity = normalize(normalizedQuery)
        var matched: [(score: Double, vm: SuggestionViewModel)] = []
        for (key, value) in grouped {
            let textLower = value.text.lowercased()
            let prefixScore = textLower.hasPrefix(normalizedQuery) ? 1.0 : 0.0
            let containsScore = textLower.contains(normalizedQuery) ? 0.6 : 0.0
            let similarity = key.contains(normalizedForSimilarity) ? 0.5 : 0.0
            let freqScore = min(1.0, Double(value.count) / 10.0)
            let timeFromLastSeen = Date().timeIntervalSince(value.lastSeen)
            let limitedDelta = min(7 * day, timeFromLastSeen)
            let recencyScore = max(0.0, 1.0 - (limitedDelta / (7 * day)))
            let score = prefixScore + containsScore + similarity + freqScore + recencyScore
            guard score > 0 else { continue }
            let vm = SuggestionViewModel(
                canonicalKey: key,
                text: value.text,
                calories: value.totals.0,
                proteins: value.totals.1,
                fats: value.totals.2,
                carbs: value.totals.3,
                source: value.source
            )
            matched.append((score, vm))
        }

        return matched
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.vm }
    }

    static func recordDataGap(
        title: String,
        fingerprint: String,
        context: ModelContext
    ) {
        guard !fingerprint.isEmpty else { return }
        let key = "gap:\(fingerprint)"
        let descriptor = FetchDescriptor<MemoryDataGap>(predicate: #Predicate { $0.key == key })
        if let existing = try? context.fetch(descriptor).first {
            existing.updatedAt = Date()
        } else {
            context.insert(
                MemoryDataGap(
                    key: key,
                    title: title,
                    itemFingerprint: fingerprint
                )
            )
        }
    }

    static func confirmDataGap(
        fingerprint: String,
        context: ModelContext
    ) {
        let key = "gap:\(fingerprint)"
        let descriptor = FetchDescriptor<MemoryDataGap>(predicate: #Predicate { $0.key == key })
        guard let gap = try? context.fetch(descriptor).first else { return }
        gap.confirmationCount += 1
        gap.updatedAt = Date()
        if gap.confirmationCount >= 2 {
            gap.resolved = true
            gap.resolvedAt = Date()
        }
    }

    static func applyHypothesisSignal(
        key: String,
        title: String,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<MemoryHypothesis>(predicate: #Predicate { $0.key == key })
        if let hypothesis = try? context.fetch(descriptor).first {
            hypothesis.signalCount += 1
            hypothesis.lastSeenAt = Date()
            if hypothesis.signalCount >= 2 && hypothesis.status == .pendingConfirmation && hypothesis.nextPromptAt == nil {
                hypothesis.nextPromptAt = Date()
            }
        } else {
            let hypothesis = MemoryHypothesis(key: key, title: title, signalCount: 1)
            context.insert(hypothesis)
        }
    }

    static func activeHypothesisPrompt(context: ModelContext) -> MemoryHypothesis? {
        let descriptor = FetchDescriptor<MemoryHypothesis>(
            sortBy: [SortDescriptor(\MemoryHypothesis.lastSeenAt, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor) else { return nil }
        let now = Date()
        return all.first { hypothesis in
            guard hypothesis.signalCount >= 2 else { return false }
            guard hypothesis.status == .pendingConfirmation || hypothesis.status == .underReview else { return false }
            if let nextPromptAt = hypothesis.nextPromptAt, nextPromptAt > now { return false }
            if let cooldown = hypothesis.cooldownUntil, cooldown > now { return false }
            return true
        }
    }

    static func confirmHypothesis(_ hypothesis: MemoryHypothesis) {
        hypothesis.status = .confirmed
        hypothesis.confirmedAt = Date()
        hypothesis.nextPromptAt = nil
        hypothesis.score = min(1.0, max(0.6, hypothesis.score + 0.2))
    }

    static func rejectHypothesis(_ hypothesis: MemoryHypothesis) {
        hypothesis.status = .rejected
        hypothesis.nextPromptAt = nil
        hypothesis.score = max(0.0, hypothesis.score - 0.4)
    }

    static func registerHypothesisConflict(_ hypothesis: MemoryHypothesis) {
        hypothesis.status = .underReview
        hypothesis.score = max(0.0, hypothesis.score - 0.25)
        hypothesis.lastConflictAt = Date()
        hypothesis.cooldownUntil = Date().addingTimeInterval(7 * day)
        hypothesis.nextPromptAt = hypothesis.cooldownUntil
    }

    static func resolveSuggestion(for rawText: String, context: ModelContext) -> MemorySuggestion? {
        let key = normalize(rawText)
        guard !key.isEmpty else { return nil }

        let canonicalKey = key
        let canonicalDescriptor = FetchDescriptor<MemorySuggestion>(
            predicate: #Predicate<MemorySuggestion> { suggestion in
                suggestion.canonicalKey == canonicalKey
            }
        )
        if let byCanonical = try? context.fetch(canonicalDescriptor).first(where: { !$0.isCandidate }) {
            return byCanonical
        }

        let aliasDescriptor = FetchDescriptor<MemorySuggestionAlias>(
            predicate: #Predicate<MemorySuggestionAlias> { alias in
                alias.text == key
            }
        )
        return (try? context.fetch(aliasDescriptor).first)?.suggestion
    }

    static func upsertPrimarySuggestion(
        text: String,
        totals: (calories: Double, proteins: Double, fats: Double, carbs: Double),
        context: ModelContext
    ) {
        let key = normalize(text)
        guard !key.isEmpty else { return }

        let canonicalKey = key
        let descriptor = FetchDescriptor<MemorySuggestion>(
            predicate: #Predicate<MemorySuggestion> { suggestion in
                suggestion.canonicalKey == canonicalKey
            }
        )

        let primary = try? context.fetch(descriptor).first(where: { !$0.isCandidate })
        if let primary {
            primary.displayText = text
            primary.usageCount += 1
            primary.lastUsedAt = Date()
            if EstimationRuntime.shouldUpdatePrimarySuggestion(oldCalories: primary.calories, newCalories: totals.calories) {
                primary.calories = totals.calories
                primary.proteins = totals.proteins
                primary.fats = totals.fats
                primary.carbs = totals.carbs
            } else {
                saveCandidate(for: primary, text: text, totals: totals, context: context)
            }
            ensureAlias(key: key, text: text, primary: primary, context: context)
            return
        }

        let created = MemorySuggestion(
            canonicalKey: key,
            displayText: text,
            calories: totals.calories,
            proteins: totals.proteins,
            fats: totals.fats,
            carbs: totals.carbs,
            usageCount: 1,
            lastUsedAt: Date(),
            version: 1,
            isFallback: false,
            isCandidate: false,
            candidateCount: 0
        )
        context.insert(created)
        ensureAlias(key: key, text: text, primary: created, context: context)
    }

    private static func ensureAlias(
        key: String,
        text: String,
        primary: MemorySuggestion,
        context: ModelContext
    ) {
        let normalizedText = normalize(text)
        guard !normalizedText.isEmpty else { return }
        let descriptor = FetchDescriptor<MemorySuggestionAlias>(
            predicate: #Predicate<MemorySuggestionAlias> { alias in
                alias.text == normalizedText
            }
        )
        if let existing = try? context.fetch(descriptor).first {
            if existing.suggestion?.persistentModelID != primary.persistentModelID {
                existing.suggestion = primary
            }
            return
        }
        context.insert(MemorySuggestionAlias(text: normalizedText, suggestion: primary))
    }

    private static func saveCandidate(
        for primary: MemorySuggestion,
        text: String,
        totals: (calories: Double, proteins: Double, fats: Double, carbs: Double),
        context: ModelContext
    ) {
        let canonicalKey = primary.canonicalKey
        let descriptor = FetchDescriptor<MemorySuggestion>(
            predicate: #Predicate<MemorySuggestion> { suggestion in
                suggestion.canonicalKey == canonicalKey
            }
        )
        if let candidate = try? context.fetch(descriptor).first(where: { $0.isCandidate }) {
            candidate.candidateCount += 1
            candidate.lastUsedAt = Date()
            if candidate.candidateCount >= 2 {
                promoteCandidate(candidate, primary: primary, context: context)
            }
            return
        }

        let candidate = MemorySuggestion(
            canonicalKey: primary.canonicalKey,
            displayText: text,
            calories: totals.calories,
            proteins: totals.proteins,
            fats: totals.fats,
            carbs: totals.carbs,
            usageCount: 1,
            lastUsedAt: Date(),
            version: primary.version + 1,
            isFallback: false,
            isCandidate: true,
            candidateCount: 1
        )
        context.insert(candidate)
    }

    private static func promoteCandidate(
        _ candidate: MemorySuggestion,
        primary: MemorySuggestion,
        context: ModelContext
    ) {
        let previousPrimaryVersion = primary.version
        primary.isFallback = true
        primary.version = previousPrimaryVersion + 1
        primary.lastUsedAt = Date()

        candidate.isCandidate = false
        candidate.isFallback = false
        candidate.version = previousPrimaryVersion + 2
        candidate.candidateCount = 0

        pruneFallbackVersions(for: candidate.canonicalKey, context: context)
    }

    private static func pruneFallbackVersions(for canonicalKey: String, context: ModelContext) {
        let targetCanonicalKey = canonicalKey
        let descriptor = FetchDescriptor<MemorySuggestion>(
            predicate: #Predicate<MemorySuggestion> { suggestion in
                suggestion.canonicalKey == targetCanonicalKey
            },
            sortBy: [SortDescriptor(\MemorySuggestion.lastUsedAt, order: .reverse)]
        )

        guard let all = try? context.fetch(descriptor), all.count > 3 else { return }
        for extra in all.dropFirst(3) {
            context.delete(extra)
        }
    }

    static func snoozeHypothesis(_ hypothesis: MemoryHypothesis) {
        hypothesis.nextPromptAt = Date().addingTimeInterval(3 * day)
    }

    static func deleteMemorySuggestion(_ suggestion: MemorySuggestion, context: ModelContext) {
        context.delete(suggestion)
    }

    static func deleteHypothesis(_ hypothesis: MemoryHypothesis, context: ModelContext) {
        context.delete(hypothesis)
    }

    static func deleteDataGap(_ gap: MemoryDataGap, context: ModelContext) {
        context.delete(gap)
    }

    static func wipeAllMemory(context: ModelContext) {
        if let suggestions = try? context.fetch(FetchDescriptor<MemorySuggestion>()) {
            for suggestion in suggestions { context.delete(suggestion) }
        }
        if let aliases = try? context.fetch(FetchDescriptor<MemorySuggestionAlias>()) {
            for alias in aliases { context.delete(alias) }
        }
        if let hypotheses = try? context.fetch(FetchDescriptor<MemoryHypothesis>()) {
            for hypothesis in hypotheses { context.delete(hypothesis) }
        }
        if let gaps = try? context.fetch(FetchDescriptor<MemoryDataGap>()) {
            for gap in gaps { context.delete(gap) }
        }
    }
}
