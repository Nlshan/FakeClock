import SwiftUI
import Combine

/// Routes alarm-notification actions (Stop / Snooze) from the system notification
/// center to the currently mounted `AlarmViewModel`.
///
/// The app delegate posts `timerLockAlarmAction` on the main queue whenever a
/// user taps Stop or Snooze on an alarm notification. This object owns the
/// subscription and hands the action to the bound view model, so the
/// translation from `UNNotificationResponse` to domain logic lives in one
/// place and is unit-testable with a fake notification center.
@MainActor
final class AlarmActionHandler: ObservableObject {
    private var viewModel: AlarmViewModel?
    private var cancellable: AnyCancellable?

    /// Binds the handler to a view model. The previous binding is released so
    /// only the currently mounted tab can act on an alarm.
    func bind(_ viewModel: AlarmViewModel) {
        self.viewModel = viewModel
        cancellable = NotificationCenter.default.publisher(for: .timerLockAlarmAction)
            .sink { [weak self] note in
                guard let self, let viewModel = self.viewModel else { return }
                self.apply(note: note, to: viewModel)
            }
    }

    func unbind() {
        cancellable?.cancel()
        cancellable = nil
        viewModel = nil
    }

    private func apply(note: Notification, to viewModel: AlarmViewModel) {
        guard let action = note.userInfo?[NotificationService.alarmActionUserInfoKey] as? String,
              let idString = note.userInfo?[UserNotificationScheduler.alarmIDUserInfoKey] as? String,
              let alarmID = UUID(uuidString: idString) else { return }

        if action == UserNotificationScheduler.stopActionIdentifier {
            if let alarm = viewModel.alarms.first(where: { $0.id == alarmID }) {
                viewModel.dismiss(alarm: alarm)
            }
        } else if action == UserNotificationScheduler.snoozeActionIdentifier {
            if let alarm = viewModel.alarms.first(where: { $0.id == alarmID }) {
                Task {
                    try? await viewModel.notificationService.scheduleSnooze(
                        alarmID: alarm.id,
                        label: alarm.label,
                        sound: alarm.sound
                    )
                }
            }
        }
    }
}