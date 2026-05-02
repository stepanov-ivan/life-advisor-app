import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false
    @Published var pendingLogWindow: String?
    @Published var pendingSkipWindow: String?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    func scheduleMealWindowNotifications(windows: [MealWindow]) {
        let center = UNUserNotificationCenter.current()

        center.removeAllPendingNotificationRequests()

        for window in windows {
            let content = UNMutableNotificationContent()
            content.title = "\(window.name)"
            content.body = "Запиши, что ты съел"
            content.sound = .default
            content.categoryIdentifier = "MEAL_WINDOW"
            content.userInfo = ["windowLabel": window.name]

            var dateComponents = DateComponents()
            dateComponents.hour = window.endHour
            dateComponents.minute = window.endMinute

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: true
            )

            let request = UNNotificationRequest(
                identifier: "meal-\(window.name)",
                content: content,
                trigger: trigger
            )

            center.add(request)
        }
    }

    func scheduleEndOfDayReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Не все приёмы записаны"
        content.body = "Заполни оставшиеся, чтобы получить совет дня"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 22
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: dateComponents,
            repeats: true
        )

        let request = UNNotificationRequest(
            identifier: "end-of-day-reminder",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    func scheduleAdviceReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Твой совет дня готов"
        content.body = "Открой приложение, чтобы узнать анализ питания"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 7200,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "advice-reminder",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    func registerCategories() {
        let logAction = UNNotificationAction(
            identifier: "LOG_MEAL",
            title: "Записать",
            options: .foreground
        )

        let skipAction = UNNotificationAction(
            identifier: "SKIP_MEAL",
            title: "Не ел",
            options: []
        )

        let remindLaterAction = UNNotificationAction(
            identifier: "REMIND_LATER",
            title: "Напомнить позже",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "MEAL_WINDOW",
            actions: [logAction, skipAction, remindLaterAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        switch response.actionIdentifier {
        case "LOG_MEAL":
            if let windowLabel = response.notification.request.content.userInfo["windowLabel"] as? String {
                pendingLogWindow = windowLabel
            }
        case "SKIP_MEAL":
            if let windowLabel = response.notification.request.content.userInfo["windowLabel"] as? String {
                pendingSkipWindow = windowLabel
            }
        case "REMIND_LATER":
            let content = response.notification.request.content
            let laterRequest = UNNotificationRequest(
                identifier: "reminder-\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1800, repeats: false)
            )
            try? await center.add(laterRequest)
        default:
            break
        }
    }
}
