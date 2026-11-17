import SwiftUI
import UserNotifications

/// Application entry point.
///
/// Owns the single `AppState` (composition root) and forwards notification
/// lifecycle events to it. The delegate exists only for the pieces SwiftUI's
/// `App` protocol cannot express: notification category registration and
/// foreground presentation behavior.
@main
struct TimerLockApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState

    init() {
        // Build the composition root before the first body evaluation so the
        // lock decision is synchronous (§10, no protected-content flash).
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            AppCoordinator()
                .environmentObject(appState)
                .onReceive(NotificationCenter.default.publisher(for: .timerLockOpenTab)) { note in
                    if let raw = note.userInfo?[AppTab.openTabUserInfoKey] as? String,
                       let tab = AppTab(rawValue: raw) {
                        appState.pendingTab = tab
                    }
                }
        }
    }
}

// MARK: - Delegate

/// Notification-center plumbing. Registered categories control the alarm
/// actions (Snooze / Stop); foreground presentation keeps alarms audible
/// while Timer Lock is open, which matches user expectations for an alarm app.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let scheduler = UserNotificationScheduler()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        scheduler.requestCategories()
        return true
    }

    // Alarms must be heard while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    // Tap handling: route alarm taps to the Alarm tab, timer taps to Timer,
    // and let the relevant view model consume the event (dismiss/snooze).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo as? [String: String] ?? [:]

        if identifier == NotificationService.timerIdentifier {
            NotificationCenter.default.post(
                name: .timerLockOpenTab,
                object: nil,
                userInfo: [AppTab.openTabUserInfoKey: AppTab.timer.rawValue]
            )
        } else if identifier.hasPrefix(NotificationService.alarmIdentifierPrefix) {
            if let alarmID = NotificationService.alarmID(from: userInfo) {
                NotificationCenter.default.post(
                    name: .timerLockAlarmAction,
                    object: nil,
                    userInfo: [
                        NotificationService.alarmActionUserInfoKey: response.actionIdentifier,
                        UserNotificationScheduler.alarmIDUserInfoKey: alarmID.uuidString,
                    ]
                )
            }
            NotificationCenter.default.post(
                name: .timerLockOpenTab,
                object: nil,
                userInfo: [AppTab.openTabUserInfoKey: AppTab.alarm.rawValue]
            )
        }
        completionHandler()
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted by the app delegate when a notification tap should open a tab.
    static let timerLockOpenTab = Notification.Name("timerlock.openTab")
    /// Posted for alarm notification actions (Stop / Snooze).
    static let timerLockAlarmAction = Notification.Name("timerlock.alarmAction")
}

extension AppTab {
    static let openTabUserInfoKey = "tab"
}

extension NotificationService {
    static let alarmActionUserInfoKey = "action"
}
