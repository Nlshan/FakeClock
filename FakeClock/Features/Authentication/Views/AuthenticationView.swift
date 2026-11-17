import SwiftUI

/// The authentication gate screen (§9.2). Visually a timer configuration
/// screen: dial header, wheel columns, one confirm action.
struct AuthenticationView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var viewModel: UnlockViewModel

    init(authManager: AuthenticationManager, lockManager: LockManager, biometrics: BiometricService, settingsProvider: @escaping () -> AppSettings) {
        _viewModel = StateObject(wrappedValue: UnlockViewModel(
            authManager: authManager,
            lockManager: lockManager,
            biometrics: biometrics,
            settingsProvider: settingsProvider
        ))
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            if viewModel.needsRecovery {
                recovery
            } else {
                content
            }
        }
        .accessibilityIdentifier(A11y.lockScreen)
    }

    // MARK: Normal lock

    private var content: some View {
        VStack(spacing: Theme.Metrics.spacingXL) {
            Spacer(minLength: Theme.Metrics.spacingXL)

            DurationDialHeader(
                hours: viewModel.hours,
                minutes: viewModel.minutes,
                title: "Timer Lock",
                accessibilityHint: "The wheels below set the duration. Confirm to unlock."
            )

            DurationPickerColumns(hours: $viewModel.hours, minutes: $viewModel.minutes)
                .onChange(of: viewModel.hours) { _ in viewModel.selectionChanged() }
                .onChange(of: viewModel.minutes) { _ in viewModel.selectionChanged() }
                .padding(.horizontal, Theme.Metrics.spacingL)

            failureBanner

            VStack(spacing: Theme.Metrics.spacingM) {
                Button {
                    viewModel.submit()
                } label: {
                    Label("Set Timer", systemImage: "lock.open")
                }
                .buttonStyle(.tlPrimary)
                .disabled(!viewModel.canSubmit)
                .opacity(viewModel.canSubmit ? 1 : 0.45)
                .accessibilityIdentifier(A11y.unlockButton)

                if viewModel.showsBiometricOption {
                    Button {
                        Task { await viewModel.attemptBiometric() }
                    } label: {
                        HStack(spacing: Theme.Metrics.spacingS) {
                            Image(systemName: viewModel.biometricLabel == "Face ID" ? "faceid" : "touchid")
                            Text("Unlock with \(viewModel.biometricLabel)")
                        }
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isBiometricPending)
                    .accessibilityIdentifier(A11y.biometricButton)
                }
            }
            .padding(.horizontal, Theme.Metrics.spacingXL)

            Spacer()
        }
    }

    private var failureBanner: some View {
        Group {
            if let message = viewModel.failureMessage {
                HStack(spacing: Theme.Metrics.spacingS) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Palette.danger)
                    Text(message)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, Theme.Metrics.spacingL)
                .padding(.vertical, Theme.Metrics.spacingS)
                .background(Capsule().fill(Theme.Palette.danger.opacity(0.12)))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.failureMessage)
    }

    // MARK: Recovery (§18: credential lost but setup marked complete)

    private var recovery: some View {
        VStack(spacing: Theme.Metrics.spacingL) {
            Spacer()
            Image(systemName: "lock.rotation")
                .font(.system(size: 44))
                .foregroundStyle(Theme.Palette.accent)
            Text("Security reset required")
                .font(Theme.Typography.headline)
            Text("The stored duration can't be read on this device. You'll set a new one; your clock, alarms and laps stay untouched.")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Metrics.spacingXL)
            Button {
                viewModel.resetAndRecover()
            } label: {
                Text("Set a new duration")
            }
            .buttonStyle(.tlPrimary)
            .padding(.horizontal, Theme.Metrics.spacingXL)
            Spacer()
        }
    }
}
