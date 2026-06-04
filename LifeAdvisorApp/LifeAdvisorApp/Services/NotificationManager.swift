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
        let language = AppLanguageManager.shared.effectiveLanguage

        center.removeAllPendingNotificationRequests()

        for window in windows {
            let content = UNMutableNotificationContent()
            content.title = window.localizedName(language: language)
            content.body = LocalizationHelper.localized("Запиши, что ты съел", table: "Localizable", language: language)
            content.sound = .default
            content.categoryIdentifier = "MEAL_WINDOW"
            content.userInfo = ["windowId": window.windowId]

            var dateComponents = DateComponents()
            dateComponents.hour = window.endHour
            dateComponents.minute = window.endMinute

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: dateComponents,
                repeats: true
            )

            let request = UNNotificationRequest(
                identifier: "meal-\(window.windowId)",
                content: content,
                trigger: trigger
            )

            center.add(request)
        }
    }

    func scheduleEndOfDayReminder() {
        let language = AppLanguageManager.shared.effectiveLanguage
        let content = UNMutableNotificationContent()
        content.title = LocalizationHelper.localized("Не все приёмы записаны", table: "Localizable", language: language)
        content.body = LocalizationHelper.localized("Заполни оставшиеся, чтобы получить совет дня", table: "Localizable", language: language)
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
        let language = AppLanguageManager.shared.effectiveLanguage
        let content = UNMutableNotificationContent()
        content.title = LocalizationHelper.localized("Твой совет дня готов", table: "Localizable", language: language)
        content.body = LocalizationHelper.localized("Открой приложение, чтобы узнать анализ питания", table: "Localizable", language: language)
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
        let language = AppLanguageManager.shared.effectiveLanguage
        let logAction = UNNotificationAction(
            identifier: "LOG_MEAL",
            title: LocalizationHelper.localized("Записать", table: "Localizable", language: language),
            options: .foreground
        )

        let skipAction = UNNotificationAction(
            identifier: "SKIP_MEAL",
            title: LocalizationHelper.localized("Не ел", table: "Localizable", language: language),
            options: []
        )

        let remindLaterAction = UNNotificationAction(
            identifier: "REMIND_LATER",
            title: LocalizationHelper.localized("Напомнить позже", table: "Localizable", language: language),
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
            if let windowId = response.notification.request.content.userInfo["windowId"] as? String {
                pendingLogWindow = windowId
            }
        case "SKIP_MEAL":
            if let windowId = response.notification.request.content.userInfo["windowId"] as? String {
                pendingSkipWindow = windowId
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
