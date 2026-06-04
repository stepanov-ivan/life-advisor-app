import Foundation

enum DashboardDateLogic {
    struct DayRange {
        let start: Date
        let end: Date
    }

    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func dayRange(for date: Date, calendar: Calendar = .current) -> DayRange {
        let start = startOfDay(date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return DayRange(start: start, end: end)
    }

    static func isFutureDate(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        startOfDay(date, calendar: calendar) > startOfDay(now, calendar: calendar)
    }

    static func weekDates(around date: Date, calendar: Calendar = .current) -> [Date] {
        let startOfWeek = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        ) ?? date
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: startOfWeek) }
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = dayKeyFormatter(calendar: calendar)
        return formatter.string(from: startOfDay(date, calendar: calendar))
    }

    static func date(from dayKey: String, calendar: Calendar = .current) -> Date? {
        let formatter = dayKeyFormatter(calendar: calendar)
        guard let parsed = formatter.date(from: dayKey) else { return nil }
        return startOfDay(parsed, calendar: calendar)
    }

    private static func dayKeyFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
