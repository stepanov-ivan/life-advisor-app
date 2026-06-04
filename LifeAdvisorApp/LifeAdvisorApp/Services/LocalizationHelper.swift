import Foundation

struct LocalizationHelper {
    static func localized(_ key: String, table: String, language: AppLanguage) -> String {
        let locale = language == .system ? Locale.current : Locale(identifier: language == .ru ? "ru" : "en")
        if let path = Bundle.main.path(forResource: locale.language.languageCode?.identifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            let result = bundle.localizedString(forKey: key, value: nil, table: table)
            if result != key { return result }
        }

        if let enPath = Bundle.main.path(forResource: "en", ofType: "lproj"),
           let enBundle = Bundle(path: enPath) {
            return enBundle.localizedString(forKey: key, value: key, table: table)
        }

        return NSLocalizedString(key, tableName: table, bundle: .main, value: key, comment: "")
    }

    static func localized(_ key: String, table: String) -> String {
        localized(key, table: table, language: AppLanguageManager.currentEffectiveLanguage)
    }
}
