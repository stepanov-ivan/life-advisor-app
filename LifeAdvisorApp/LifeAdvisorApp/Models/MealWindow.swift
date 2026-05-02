import Foundation
import SwiftData

@Model
final class MealWindow {
    @Attribute(.unique) var name: String
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var order: Int

    init(
        name: String,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        order: Int
    ) {
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
}
