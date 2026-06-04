import Foundation

@MainActor
final class AppLanguageManager: ObservableObject {
    static let shared = AppLanguageManager()
    static let overrideKey = "app_language_override"

    @Published var override: AppLanguage = .system

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.overrideKey),
           let saved = AppLanguage(rawValue: raw) {
            override = saved
        }
    }

    nonisolated static var currentEffectiveLanguage: AppLanguage {
        let currentOverride: AppLanguage
        if let raw = UserDefaults.standard.string(forKey: overrideKey),
           let saved = AppLanguage(rawValue: raw) {
            currentOverride = saved
        } else {
            currentOverride = .system
        }
        if currentOverride != .system { return currentOverride }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("ru") { return .ru }
        return .en
    }

    nonisolated var effectiveLanguage: AppLanguage {
        Self.currentEffectiveLanguage
    }

    nonisolated var locale: Locale {
        switch effectiveLanguage {
        case .ru: return Locale(identifier: "ru_RU")
        case .en: return Locale(identifier: "en_US")
        case .system: return Locale.current
        }
    }

    func setOverride(_ language: AppLanguage) {
        override = language
        UserDefaults.standard.set(language.rawValue, forKey: Self.overrideKey)
    }
}
