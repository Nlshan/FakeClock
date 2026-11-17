import SwiftUI

/// Alarm tab (§6). A list of alarms with per-alarm toggles and a header that
/// shows the next alarm, plus the add/edit sheet and the notification-action
/// handler that routes Stop/Snooze from the system center.
struct AlarmView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var viewModel: AlarmViewModel
    @StateObject private var actionHandler = AlarmActionHandler()

    init(persistence: PersistenceServicing = PersistenceService(defaults: .standard),
         notificationService: NotificationService = NotificationService(scheduler: UserNotificationScheduler())) {
        _viewModel = StateObject(wrappedValue: AlarmViewModel(persistence: persistence, notificationService: notificationService))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.Metrics.spacingM) {
                    nextAlarmHeader
                        .padding(.top, Theme.Metrics.spacingS)

                    if viewModel.alarms.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.alarms) { alarm in
                            alarmRow(alarm)
                        }
                    }
                }
                .padding(.horizontal, Theme.Metrics.spacingL)
                .padding(.bottom, Theme.Metrics.spacingXXL)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Alarm")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add alarm")
                    .accessibilityIdentifier(A11y.addAlarmButton)
                }
                ToolbarItem(placement: .topBarLeading) {
                    SettingsLinkCompat {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingEditor) {
                AlarmEditView(mode: .create) { alarm in
                    viewModel.addAlarm(hour: alarm.hour, minute: alarm.minute, label: alarm.label, sound: alarm.sound, repeatDays: alarm.repeatDays)
                }
            }
            .onAppear {
                Task { await viewModel.syncAll() }
                actionHandler.bind(viewModel)
            }
            .onDisappear {
                actionHandler.unbind()
            }
            .accessibilityIdentifier(A11y.alarmScreen)
        }
    }

    // MARK: Header

    private var nextAlarmHeader: some View {
        let next = viewModel.nextAlarm
        return HStack(spacing: Theme.Metrics.spacingM) {
            Image(systemName: next == nil ? "bell.slash" : "bell.fill")
                .font(.system(size: 22))
                .foregroundStyle(next == nil ? Theme.Palette.textSecondary : Theme.Palette.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(next == nil ? "No alarm set" : "Next alarm")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                if let next {
                    Text("\(next.alarm.timeString) · \(TimeFormat.untilNextAlarm(next.date.timeIntervalSinceNow))")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(Theme.Metrics.spacingL)
        .cardStyle()
    }

    // MARK: Rows

    private var emptyState: some View {
        VStack(spacing: Theme.Metrics.spacingM) {
            Image(systemName: "alarm")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Palette.textSecondary)
            Text("No alarms yet")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("Tap + to set your first alarm.")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Metrics.spacingXXL)
    }

    private func alarmRow(_ alarm: Alarm) -> some View {
        let syncError = viewModel.syncFailure(for: alarm.id)
        return HStack(alignment: .center, spacing: Theme.Metrics.spacingM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(alarm.timeString)
                    .font(Theme.Typography.display(32))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .monospacedDigit()
                if alarm.hasLabel {
                    Text(alarm.label)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
                Text(alarm.repeatSummary())
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                if let syncError {
                    Text(syncError.errorDescription ?? "Sync failed")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Palette.danger)
                }
            }

            Spacer(minLength: Theme.Metrics.spacingM)

            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { _ in viewModel.toggle(alarm) }
            ))
            .tint(Theme.Palette.accent)
            .accessibilityLabel("Toggle \(alarm.timeString)")
        }
        .padding(.horizontal, Theme.Metrics.spacingL)
        .padding(.vertical, Theme.Metrics.spacingM)
        .cardStyle(cornerRadius: Theme.Metrics.cornerM)
        .swipeActions {
            Button {
                showingEditor = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Theme.Palette.accent)

            Button(role: .destructive) {
                viewModel.delete(alarm)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(alarm.timeString), \(alarm.hasLabel ? alarm.label + ", " : "")\(alarm.repeatSummary()), \(alarm.isEnabled ? "on" : "off")")
    }
}