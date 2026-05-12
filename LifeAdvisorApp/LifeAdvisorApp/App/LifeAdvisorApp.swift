import SwiftUI
import SwiftData

@main
struct LifeAdvisorApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    private static let schemaResetVersion = "unify-memory-meal-structure-v1"
    private static let schemaResetVersionKey = "storage_schema_reset_version"

    let modelContainer: ModelContainer

    init() {
        Self.applyOneShotSchemaResetIfNeeded()

        let schema = Schema([
            MealEvent.self,
            EstimateItem.self,
            MemorySuggestion.self,
            MemorySuggestionAlias.self,
            MemoryHypothesis.self,
            MemoryDataGap.self,
            MealWindow.self,
            DailyAdvice.self,
            Recommendation.self
        ])

        let configuration = ModelConfiguration(
            "default",
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Destructive reset for incompatible schemas during active development.
            Self.deleteKnownSwiftDataStoreFiles()
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }

        setupDefaultMealWindowsIfNeeded()
        purgeExpiredRawPayloads()
        purgeExpiredMemoryArtifacts()
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .modelContainer(modelContainer)
    }

    private func setupDefaultMealWindowsIfNeeded() {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<MealWindow>()
        guard let count = try? context.fetchCount(descriptor), count == 0 else { return }

        let windows: [(String, Int, Int, Int, Int)] = [
            ("Завтрак", 7, 0, 10, 0),
            ("Обед", 12, 0, 15, 0),
            ("Ужин", 18, 0, 21, 0)
        ]

        for (i, (name, sh, sm, eh, em)) in windows.enumerated() {
            let window = MealWindow(
                name: name,
                startHour: sh,
                startMinute: sm,
                endHour: eh,
                endMinute: em,
                order: i
            )
            context.insert(window)
        }
        try? context.save()
    }

    private func purgeExpiredRawPayloads() {
        let context = modelContainer.mainContext
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date.distantPast
        let descriptor = FetchDescriptor<MealEvent>()
        guard let events = try? context.fetch(descriptor) else { return }

        for event in events {
            if let createdAt = event.rawPayloadCreatedAt, createdAt < cutoff {
                event.rawPayload = nil
                event.rawPayloadCreatedAt = nil
                if event.parseErrorSummary?.isEmpty == true {
                    event.parseErrorSummary = nil
                }
            }
        }

        try? context.save()
    }

    private func purgeExpiredMemoryArtifacts() {
        let context = modelContainer.mainContext
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date.distantPast

        let gapDescriptor = FetchDescriptor<MemoryDataGap>()
        if let gaps = try? context.fetch(gapDescriptor) {
            for gap in gaps where gap.updatedAt < cutoff {
                context.delete(gap)
            }
        }

        let hypothesisDescriptor = FetchDescriptor<MemoryHypothesis>()
        if let hypotheses = try? context.fetch(hypothesisDescriptor) {
            for hypothesis in hypotheses where hypothesis.status == .pendingConfirmation && hypothesis.lastSeenAt < cutoff {
                context.delete(hypothesis)
            }
        }

        try? context.save()
    }

    private static func deleteKnownSwiftDataStoreFiles() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let candidateBases: [URL] = [
            appSupport,
            appSupport?.appendingPathComponent("default.store"),
            appSupport?.appendingPathComponent("default.sqlite"),
            appSupport?.appendingPathComponent("LifeAdvisorApp/default.store"),
            appSupport?.appendingPathComponent("LifeAdvisorApp/default.sqlite")
        ]
        .compactMap { $0 }

        let suffixes = ["", "-wal", "-shm"]
        for base in candidateBases {
            for suffix in suffixes {
                let file = URL(fileURLWithPath: base.path + suffix)
                if fm.fileExists(atPath: file.path) {
                    try? fm.removeItem(at: file)
                }
            }
        }

        guard let appSupport else { return }
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let files = try? fm.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        let removablePrefixes = ["default.store", "default.sqlite"]
        for file in files {
            let name = file.lastPathComponent
            if removablePrefixes.contains(where: { name.hasPrefix($0) }) {
                try? fm.removeItem(at: file)
            }
        }
    }

    private static func applyOneShotSchemaResetIfNeeded() {
        let defaults = UserDefaults.standard
        let current = defaults.string(forKey: schemaResetVersionKey)
        guard current != schemaResetVersion else { return }
        deleteKnownSwiftDataStoreFiles()
        defaults.set(schemaResetVersion, forKey: schemaResetVersionKey)
    }
}
