import Foundation

enum MemoryPresentation {
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
}
