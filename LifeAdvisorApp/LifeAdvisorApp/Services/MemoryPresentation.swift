import Foundation

enum MemoryPresentation {
    static let minAdviceLength = 40
    private static let blockedAdviceFragments = [
        "источник структуры",
        "уверенность модели",
        "режим оценки"
    ]

    static func shouldPromptOutOfSync(
        source: StructureSource,
        selectedText: String?,
        currentText: String
    ) -> Bool {
        guard source == .memorySuggestion else { return false }
        return MemoryEngine.isOutOfSync(selectedText: selectedText, currentText: currentText)
    }

    static func explainabilityFactors(
        source: StructureSource,
        confidence: String?,
        memoryApplied: Bool,
        sourceMode: EstimateSourceMode?,
        items: [EstimateItem]
    ) -> [String] {
        var factors: [String] = []
        factors.append("Источник структуры: \(source.rawValue)")
        if let confidence {
            factors.append("Уверенность модели: \(confidence)")
        }
        if memoryApplied {
            factors.append("Применён memory prior из прошлых логов")
        }
        factors.append(contentsOf: items.prefix(4).map { "\($0.name): \($0.reason)" })
        if let sourceMode {
            factors.append("Режим оценки: \(sourceMode.rawValue)")
        }
        return factors
    }

    static func topExplainabilityFactors(
        _ factors: [String],
        showAll: Bool
    ) -> [String] {
        showAll ? factors : Array(factors.prefix(2))
    }

    static func isAdviceUseful(_ text: String?) -> Bool {
        guard let text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minAdviceLength else { return false }
        let lower = trimmed.lowercased()
        return !blockedAdviceFragments.contains(where: { lower.contains($0) })
    }

    static func cleanAdviceText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAdviceUseful(trimmed) else { return nil }
        return trimmed
    }
}
