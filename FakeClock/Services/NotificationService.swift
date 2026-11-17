import Foundation
import UserNotifications

// MARK: - Errors and status

/// Structured notification errors with copy safe to display.
enum NotificationError: LocalizedError, Equatable {
    case denied
    case schedulingFailed(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Notifications are turned off for Timer Lock. Re-enable them in the iOS Settings app to get alarms."
        case .schedulingFailed(let reason):
            return "Could not schedule the alert: \(reason)"
        case .unavailable:
            return "Notifications are unavailable right now."
        }
    }
}

/// Delivery permission snapshot surfaced in the UI so the user always knows
/// whether their alarms can actually fire.
struct NotificationAuthorization: Equatable {
    enum State: Equatable {
        case notDetermined
        case granted
        case provisional
        case denied
        case unavailable
    }

    var state: State
    var showsBadge: Bool

    var canDeliver: Bool { state == .granted || state == .provisional }
}

// MARK: - Plan value type

/// Framework-free description of a notification the app wants scheduled.
///
/// Tests assert against plans (identifier, timing, repeat semantics) without
/// requiring an app container, which makes the scheduling *logic*
/// unit-testable: `UNUserNotificationCenter` cannot run inside a plain unit
/// test target on macOS CI, so the logic layer is verified here and the thin
/// translation layer is verified on-device.
struct NotificationPlan: Equatable {
    enum Timing: Equatable {
        /// Wall-clock components resolved by the OS calendar trigger.
        case calendar(DateComponents, repeats: Bool)
        /// Fixed interval from scheduling time.
        case interval(TimeInterval)
    }

    var identifier: String
    var title: String
    var body: String
    var timing: Timing
    var soundEnabled: Bool
    var categoryIdentifier: String
    var userInfo: [String: String]
}

// MARK: - Scheduling abstraction

protocol NotificationScheduling: AnyObject {
    func authorizationState() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
    func schedule(_ plan: NotificationPlan) async throws
    func cancel(identifiers: [String]) async
    func cancelAllScheduled() async
    func removeDelivered(withIdentifiers identifiers: [String]) async
}

/// `UNUserNotificationCenter`-backed scheduler. Translation layer only — all
/// decisions are made upstream in `NotificationService` / view models.
final class UserNotificationScheduler: NotificationScheduling {
    static let alarmCategoryIdentifier = "timerlock.category.alarm"
    static let timerCategoryIdentifier = "timerlock.category.timer"
    static let snoozeActionIdentifier = "timerlock.action.snooze"
    static let stopActionIdentifier = "timerlock.action.stop"

    static let alarmIDUserInfoKey = "alarmID"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Registers actionable categories. Called once from the app delegate.
    func requestCategories() {
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionIdentifier,
            title: "Snooze 5 min",
            options: []
        )
        let stop = UNNotificationAction(
            identifier: Self.stopActionIdentifier,
            title: "Stop",
            options: [.destructive]
        )
        let alarmCategory = UNNotificationCategory(
            identifier: Self.alarmCategoryIdentifier,
            actions: [snooze, stop],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let timerCategory = UNNotificationCategory(
            identifier: Self.timerCategoryIdentifier,
            actions: [stop],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([alarmCategory, timerCategory])
    }

    func authorizationState() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        let badge = settings.badgeSetting == .enabled
        switch settings.authorizationStatus {
        case .notDetermined:
            return NotificationAuthorization(state: .notDetermined, showsBadge: badge)
        case .authorized:
            return NotificationAuthorization(state: .granted, showsBadge: badge)
        case .provisional:
            return NotificationAuthorization(state: .provisional, showsBadge: badge)
        case .denied:
            return NotificationAuthorization(state: .denied, showsBadge: false)
        default:
            return NotificationAuthorization(state: .unavailable, showsBadge: false)
        }
    }

    func requestAuthorization() async -> NotificationAuthorization {
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return NotificationAuthorization(state: .unavailable, showsBadge: false)
        }
        if granted {
            return await authorizationState()
        }
        return NotificationAuthorization(state: .denied, showsBadge: false)
    }

    func schedule(_ plan: NotificationPlan) async throws {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = plan.soundEnabled ? .default : nil
        content.categoryIdentifier = plan.categoryIdentifier
        content.userInfo = plan.userInfo

        let trigger: UNNotificationTrigger
        switch plan.timing {
        case .calendar(let components, let repeats):
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        case .interval(let seconds):
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        }

        let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                center.add(request) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? "system error"
            throw NotificationError.schedulingFailed(reason)
        }
    }

    func cancel(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func cancelAllScheduled() async {
        center.removeAllPendingNotificationRequests()
    }

    func removeDelivered(withIdentifiers identifiers: [String]) async {
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

// MARK: - Service

/// App-level notification decisions: which plan each feature needs, and
/// keeping scheduled requests consistent with visible state.
///
/// Two iOS facts shape this design, both documented in the README:
///  1. A repeating `UNCalendarNotificationTrigger` matches ONE weekday, so a
///     Mon/Wed/Fri alarm becomes three pending requests (`.wd2`, `.wd4`,
///     `.wd7` suffixes). This mirrors how the Clock-style repeat UX is built
///     on public APIs.
///  2. Local notifications are best-effort. They survive termination and
///     restart once scheduled, but delivery is subject to system load, Low
///     Power Mode, Focus filters, and the 64-pending-request cap; a normal
///     third-party app cannot run an unrestricted background alarm service.
///     Timer Lock therefore keeps each alarm's switch in sync with its
///     pending requests and surfaces permission state honestly rather than
///     promising guaranteed firing (spec §6).
final class NotificationService {
    static let alarmIdentifierPrefix = "timerlock.alarm."
    static let timerIdentifier = "timerlock.timer.completion"
    static let snoozeInterval: TimeInterval = 5 * 60

    private let scheduler: NotificationScheduling

    init(scheduler: NotificationScheduling) {
        self.scheduler = scheduler
    }

    // MARK: Identifiers

    static func alarmIdentifier(for alarmID: UUID, weekday: Int? = nil) -> String {
        var identifier = alarmIdentifierPrefix + alarmID.uuidString
        if let weekday {
            identifier += ".wd\(weekday)"
        }
        return identifier
    }

    /// Every identifier one alarm could own: base, seven weekday variants,
    /// and the snooze. Cancelling all of them is safe because unknown
    /// identifiers are ignored by the scheduler.
    static func allIdentifiers(for alarmID: UUID) -> [String] {
        var identifiers = [alarmIdentifier(for: alarmID)]
        identifiers.append(contentsOf: (1...7).map { alarmIdentifier(for: alarmID, weekday: $0) })
        identifiers.append(snoozeIdentifier(for: alarmID))
        return identifiers
    }

    static func snoozeIdentifier(for alarmID: UUID) -> String {
        alarmIdentifierPrefix + alarmID.uuidString + ".snooze"
    }

    static func alarmID(from userInfo: [String: String]) -> UUID? {
        userInfo[UserNotificationScheduler.alarmIDUserInfoKey].flatMap(UUID.init(uuidString:))
    }

    // MARK: Authorization

    func currentAuthorization() async -> NotificationAuthorization {
        await scheduler.authorizationState()
    }

    @discardableResult
    func requestAuthorization() async -> NotificationAuthorization {
        await scheduler.requestAuthorization()
    }

    // MARK: Planning

    /// Builds every pending-request plan for one alarm. Empty when the alarm
    /// is disabled or can never fire again.
    ///
    /// Repeating alarms plan per weekday (see class docs); the trigger
    /// carries wall-clock hour/minute/weekday with `repeats: true`, so the OS
    /// owns the weekly cadence and DST shifts (spec §5 rule: Foundation
    /// resolves zone transitions, we never compute offsets).
    func plans(for alarm: Alarm, now: Date = Date(), calendar: Calendar = .current) -> [NotificationPlan] {
        guard let firstFire = alarm.nextFireDate(now: now, calendar: calendar) else { return [] }
        let title = alarm.hasLabel ? alarm.label : "Alarm"
        let body = alarmBody(for: alarm, fireDate: firstFire, calendar: calendar)

        func userInfo() -> [String: String] {
            [UserNotificationScheduler.alarmIDUserInfoKey: alarm.id.uuidString]
        }

        if alarm.isRepeating {
            return alarm.repeatDays.sorted(by: { $0.rawValue < $1.rawValue }).map { day in
                var components = DateComponents()
                components.hour = alarm.hour
                components.minute = alarm.minute
                components.second = 0
                components.weekday = day.calendarIndex
                return NotificationPlan(
                    identifier: Self.alarmIdentifier(for: alarm.id, weekday: day.calendarIndex),
                    title: title,
                    body: body,
                    timing: .calendar(components, repeats: true),
                    soundEnabled: alarm.sound.playsSound,
                    categoryIdentifier: UserNotificationScheduler.alarmCategoryIdentifier,
                    userInfo: userInfo()
                )
            }
        }

        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: firstFire)
        components.timeZone = calendar.timeZone
        return [
            NotificationPlan(
                identifier: Self.alarmIdentifier(for: alarm.id),
                title: title,
                body: body,
                timing: .calendar(components, repeats: false),
                soundEnabled: alarm.sound.playsSound,
                categoryIdentifier: UserNotificationScheduler.alarmCategoryIdentifier,
                userInfo: userInfo()
            ),
        ]
    }

    private func alarmBody(for alarm: Alarm, fireDate: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("h:mm a")
        let time = formatter.string(from: fireDate)
        let repeatText = alarm.repeatSummary(calendar: calendar)
        return repeatText == "One time" ? "Fires at \(time)" : "\(repeatText) at \(time)"
    }

    // MARK: Sync

    /// Replaces all pending requests for one alarm with exactly what its
    /// current configuration requires — the invariant that keeps the visible
    /// switch state consistent with scheduled notifications (spec §6).
    func sync(alarm: Alarm, now: Date = Date(), calendar: Calendar = .current) async throws {
        // Clear everything this alarm could own first, so removed weekdays
        // disappear and edited times replace cleanly.
        await scheduler.cancel(identifiers: Self.allIdentifiers(for: alarm.id))
        for plan in plans(for: alarm, now: now, calendar: calendar) {
            try await scheduler.schedule(plan)
        }
    }

    /// Reschedules every alarm; failures are collected per-alarm so one bad
    /// entry cannot strand the rest. Returns alarms whose sync failed —
    /// callers show a warning and can retry from the Alarm tab header.
    @discardableResult
    func syncAll(alarms: [Alarm], now: Date = Date(), calendar: Calendar = .current) async -> [Alarm] {
        var failed: [Alarm] = []
        for alarm in alarms {
            do {
                try await sync(alarm: alarm, now: now, calendar: calendar)
            } catch {
                failed.append(alarm)
            }
        }
        return failed
    }

    func removeAlarm(alarmID: UUID) async {
        await scheduler.cancel(identifiers: Self.allIdentifiers(for: alarmID))
        await scheduler.removeDelivered(withIdentifiers: Self.allIdentifiers(for: alarmID))
    }

    // MARK: Timer

    /// One-shot completion alert for a running countdown.
    func scheduleTimerCompletion(endDate: Date, label: String, sound: AlertSound, now: Date = Date()) async throws {
        let remaining = endDate.timeIntervalSince(now)
        guard remaining > 1 else { return }
        let plan = NotificationPlan(
            identifier: Self.timerIdentifier,
            title: label,
            body: "Time is up.",
            timing: .interval(remaining),
            soundEnabled: sound.playsSound,
            categoryIdentifier: UserNotificationScheduler.timerCategoryIdentifier,
            userInfo: [:]
        )
        try await scheduler.schedule(plan)
    }

    func cancelTimerCompletion() async {
        await scheduler.cancel(identifiers: [Self.timerIdentifier])
        await scheduler.removeDelivered(withIdentifiers: [Self.timerIdentifier])
    }

    // MARK: Snooze

    func scheduleSnooze(alarmID: UUID, label: String, sound: AlertSound) async throws {
        let plan = NotificationPlan(
            identifier: Self.snoozeIdentifier(for: alarmID),
            title: label.isEmpty ? "Alarm (snoozed)" : label,
            body: "Snoozed for 5 minutes.",
            timing: .interval(Self.snoozeInterval),
            soundEnabled: sound.playsSound,
            categoryIdentifier: UserNotificationScheduler.alarmCategoryIdentifier,
            userInfo: [UserNotificationScheduler.alarmIDUserInfoKey: alarmID.uuidString]
        )
        try await scheduler.schedule(plan)
    }
}
