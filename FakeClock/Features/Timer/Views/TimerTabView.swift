import SwiftUI

/// Timer tab (§8). Circular progress ring around a large countdown, three-column
/// wheel picker for setup, and the Start/Pause/Resume/Cancel/Reset controls.
struct TimerTabView: View {
    @StateObject private var viewModel: TimerViewModel
    @EnvironmentObject private var app: AppState

    init(persistence: PersistenceServicing = PersistenceService(defaults: .standard),
         notificationService: NotificationService = NotificationService(scheduler: UserNotificationScheduler())) {
        _viewModel = StateObject(wrappedValue: TimerViewModel(persistence: persistence, notificationService: notificationService))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Metrics.spacingXL) {
                Spacer()

                // Circular progress + countdown display
                ZStack {
                    Circle()
                        .stroke(Theme.Palette.stroke, lineWidth: 10)
                        .frame(width: 260, height: 260)

                    Circle()
                        .trim(from: 0, to: viewModel.progress)
                        .stroke(
                            viewModel.isFinished ? Theme.Palette.success : Theme.Palette.accent,
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 260, height: 260)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.5), value: viewModel.progress)

                    VStack(spacing: Theme.Metrics.spacingS) {
                        Text(viewModel.remainingTime)
                            .font(Theme.Typography.display(64))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        if viewModel.isFinished {
                            Text("Time's up")
                                .font(Theme.Typography.callout)
                                .foregroundStyle(Theme.Palette.success)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Timer, \(viewModel.remainingTime) remaining"))

                // Setup picker (only when idle/finished)
                if viewModel.isIdle || viewModel.isFinished {
                    TimeOfDurationPicker(
                        hours: $viewModel.pickerHours,
                        minutes: $viewModel.pickerMinutes,
                        seconds: $viewModel.pickerSeconds
                    )
                    .padding(.horizontal, Theme.Metrics.spacingL)
                }

                // Controls
                HStack(spacing: Theme.Metrics.spacingM) {
                    if viewModel.isIdle {
                        control(label: "Start", role: .positive, action: viewModel.start)
                    } else if viewModel.isRunning {
                        control(label: "Pause", role: .neutral, action: viewModel.pause)
                        control(label: "Cancel", role: .negative, action: viewModel.cancel)
                    } else if viewModel.isPaused {
                        control(label: "Resume", role: .positive, action: viewModel.resume)
                        control(label: "Reset", role: .neutral, action: viewModel.reset)
                    }
                }
                .padding(.horizontal, Theme.Metrics.spacingXXL)

                Spacer()
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Timer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsLinkCompat {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .onChange(of: app.scenePhase) { phase in
                viewModel.handleScenePhase(phase)
            }
            .accessibilityIdentifier(A11y.timerScreen)
        }
    }

    private func control(label: String, role: CircularButtonStyle.Role, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(CircularButtonStyle(role: role, diameter: 64))
            .accessibilityIdentifier(label == "Start" ? A11y.timerStart : (label == "Pause" ? A11y.timerPause : A11y.timerCancel))
    }
}