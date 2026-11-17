import SwiftUI

/// Stopwatch tab (§7). Large digital display above split controls and a lap table.
struct StopwatchView: View {
    @StateObject private var viewModel: StopwatchViewModel
    @EnvironmentObject private var app: AppState

    init(clock: MonotonicClock = SystemClock.shared, persistence: PersistenceServicing = PersistenceService(defaults: .standard)) {
        _viewModel = StateObject(wrappedValue: StopwatchViewModel(clock: clock, persistence: persistence))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Large digital display
                VStack(spacing: 0) {
                    Spacer()
                    Text(viewModel.displayTime)
                        .font(Theme.Typography.display(80))
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, Theme.Metrics.spacingL)
                        .id("stopwatch_display")
                    Spacer()
                }
                .frame(maxHeight: 280)

                // Split controls
                HStack {
                    if viewModel.isIdle {
                        leftButton(label: "Lap", role: .neutral, action: {}).disabled(true).opacity(0.4)
                        Spacer()
                        rightButton(label: "Start", role: .positive, action: viewModel.start)
                    } else if viewModel.isRunning {
                        leftButton(label: "Lap", role: .neutral, action: viewModel.addLap)
                        Spacer()
                        rightButton(label: "Stop", role: .negative, action: viewModel.pause)
                    } else if viewModel.isPaused {
                        leftButton(label: "Reset", role: .neutral, action: viewModel.reset)
                        Spacer()
                        rightButton(label: "Start", role: .positive, action: viewModel.resume)
                    }
                }
                .padding(.horizontal, Theme.Metrics.spacingXXL)
                .padding(.bottom, Theme.Metrics.spacingXL)

                Divider().background(Theme.Palette.stroke)

                // Lap table
                lapList
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Stopwatch")
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
            .accessibilityIdentifier(A11y.stopwatchScreen)
        }
    }

    private func leftButton(label: String, role: CircularButtonStyle.Role, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(CircularButtonStyle(role: role))
            .accessibilityIdentifier(label == "Lap" ? A11y.stopwatchLap : A11y.stopwatchReset)
    }

    private func rightButton(label: String, role: CircularButtonStyle.Role, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(CircularButtonStyle(role: role))
            .accessibilityIdentifier(A11y.stopwatchStart)
    }

    private var lapList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.engine.laps.reversed()) { lap in
                    lapRow(lap)
                    Divider().padding(.leading, Theme.Metrics.spacingL).background(Theme.Palette.stroke)
                }
            }
        }
    }

    private func lapRow(_ lap: StopwatchEngine.Lap) -> some View {
        let flag = viewModel.engine.flag(for: lap.number)
        let color: Color = {
            switch flag {
            case .fastest: return Theme.Palette.success
            case .slowest: return Theme.Palette.danger
            case .none: return Theme.Palette.textPrimary
            }
        }()

        return HStack {
            Text("Lap \(lap.number)")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Text(TimeFormat.stopwatch(lap.duration))
                .font(Theme.Typography.display(20))
                .foregroundStyle(color)
        }
        .padding(.horizontal, Theme.Metrics.spacingL)
        .padding(.vertical, Theme.Metrics.spacingM)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lap \(lap.number), \(TimeFormat.stopwatch(lap.duration))")
    }
}
