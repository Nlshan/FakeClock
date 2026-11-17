import SwiftUI

/// Alarm tab state machine (§6).
///
/// All persistence is JSON via `PersistenceService`; the notification layer
/// is `NotificationService`, which this model asks to keep scheduled requests
/// consistent with the visible switches. The view model owns the list and
/// exposes only the operations the UI needs.
@MainActor
final class AlarmViewModel: ObservableObject {
    @Published var alarms: [Alarm] {
        didSet { persist() }
    }

    private let persistence: PersistenceServicing
    private let notificationService: NotificationService

    init(
        persistence: PersistenceServicing = PersistenceService(defaults: .standard),
        notificationService: NotificationService = NotificationService(scheduler: UserNotificationScheduler())
    ) {
        self.persistence = persistence
        self.notificationService = notificationService
        self.alarms = persistence.load([Alarm].self, forKey: PersistenceService.Keys.alarms) ?? []
    }

    // MARK: CRUD

    func addAlarm(hour: Int, minute: Int, label: String = "", sound: AlertSound = .default, repeatDays: Set<Weekday> = []) {
        let alarm = Alarm(hour: hour, minute: minute, label: label, isEnabled: true, repeatDays: repeatDays, sound: sound)
        alarms.append(alarm)
        Task { await sync(alarm) }
    }

    func updateAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
            Task { await sync(alarm) }
        }
    }

    func toggle(_ alarm: Alarm) {
        updateAlarm(Alarm(id: alarm.id, hour: alarm.hour, minute: alarm.minute, label: alarm.label, isEnabled: !alarm.isEnabled, repeatDays: alarm.repeatDays, sound: alarm.sound, consumed: alarm.consumed))
    }

    func delete(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
        Task { await notificationService.removeAlarm(alarmID: alarm.id) }
    }

    func deleteAll() {
        let ids = alarms.map(\.id)
        alarms.removeAll()
        for id in ids {
            Task { await notificationService.removeAlarm(alarmID: id) }
        }
    }

    /// Marks an alarm as consumed after the user dismisses its alert, so a
    /// one-shot alarm does not fire again on the next launch (§6).
    func dismiss(alarm: Alarm) {
        updateAlarm(Alarm(id: alarm.id, hour: alarm.hour, minute: alarm.minute, label: alarm.label, isEnabled: alarm.isEnabled, repeatDays: alarm.repeatDays, sound: alarm.sound, consumed: true))
    }

    // MARK: Queries

    /// The soonest alarm that will actually fire, or nil.
    var nextAlarm: (alarm: Alarm, date: Date)? {
        Alarm.nextScheduledAlarm(in: alarms)
    }

    func timeString(for alarm: Alarm, use24Hour: Bool) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate(use24Hour ? "HH:mm" : "h:mm")
        return formatter.string(from: DateComponents(hour: alarm.hour, minute: alarm.minute, second: 0, calendar: calendar) ?? Date())
    }

    // MARK: Sync

    /// Re-syncs one alarm's pending requests with its current configuration.
    /// Called on every edit/toggle so the visible switch matches reality (§6).
    func sync(_ alarm: Alarm) async {
        do {
            try await notificationService.sync(alarm: alarm)
        } catch {
            // Surface the failure via the "next alarm" line is not enough —
            // we keep a per-alarm error flag the UI can show.
            markSyncFailure(alarm.id, error)
        }
    }

    /// Re-syncs every alarm (launch, permission change, bulk edit).
    func syncAll() async {
        let failed = await notificationService.syncAll(alarms: alarms)
        for alarm in failed {
            markSyncFailure(alarm.id, NotificationError.schedulingFailed("system error"))
        }
    }

    private var syncFailures: [UUID: NotificationError] = [:]
    func syncFailure(for alarmID: UUID) -> NotificationError? { syncFailures[alarmID] }

    private func markSyncFailure(_ alarmID: UUID, _ error: NotificationError) {
        syncFailures[alarmID] = error
    }

    private func persist() {
        persistence.save(alarms, forKey: PersistenceService.Keys.alarms)
    }
}