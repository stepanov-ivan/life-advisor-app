import Foundation
import SwiftData

@Model
final class MealWindow {
    @Attribute(.unique) var windowId: String
    var name: String
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var order: Int

    init(
        windowId: String,
        name: String,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        order: Int
    ) {
        self.windowId = windowId
        self.name = name
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.order = order
    }

    var startTimeString: String {
        String(format: "%02d:%02d", startHour, startMinute)
    }

    var endTimeString: String {
        String(format: "%02d:%02d", endHour, endMinute)
    }

    func endDateComponents() -> DateComponents {
        DateComponents(hour: endHour, minute: endMinute)
    }

    static let defaultWindowIds = ["breakfast", "lunch", "dinner"]

    var isSystemDefault: Bool {
        Self.defaultWindowIds.contains(windowId)
    }

    func localizedName(language: AppLanguage = AppLanguageManager.currentEffectiveLanguage) -> String {
        guard isSystemDefault else { return name }
        let key: String
        switch windowId {
        case "breakfast": key = "breakfast_name"
        case "lunch": key = "lunch_name"
        case "dinner": key = "dinner_name"
        default: return name
        }
        return LocalizationHelper.localized(key, table: "Localizable", language: language)
    }
}
