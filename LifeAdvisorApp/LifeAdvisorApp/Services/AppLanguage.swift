import Foundation

enum AppLanguage: String, CaseIterable, Codable {
    case system = "system"
    case en = "en"
    case ru = "ru"

    var displayNameKey: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .ru: return "Русский"
        }
    }
}
