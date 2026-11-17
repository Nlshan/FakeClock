import SwiftUI

/// First-run credential creation and the in-Settings rotation flow (§9.1).
/// Shares the timer-look of `AuthenticationView`, but reads as "set up a new
/// timer". After `isComplete`, the caller moves on.
struct SetupAuthenticationView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var viewModel: SetupAuthenticationViewModel

    init(
        authManager: AuthenticationManager,
        lockManager: LockManager,
        mode: SetupAuthenticationViewModel.Mode = .initialSetup,
        onFinish: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(wrappedValue: SetupAuthenticationViewModel(
            authManager: authManager,
            lockManager: lockManager,
            mode: mode,
            onFinish: onFinish
        ))
    }

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            VStack(spacing: Theme.Metrics.spacingXL) {
                Spacer(minLength: Theme.Metrics.spacingXL)

                DurationDialHeader(
                    hours: viewModel.hours,
                    minutes: viewModel.minutes,
                    title: viewModel.instructionText
                )

                DurationPickerColumns(hours: $viewModel.hours, minutes: $viewModel.minutes)
                    .onChange(of: viewModel.hours) { _ in viewModel.selectionChanged() }
                    .onChange(of: viewModel.minutes) { _ in viewModel.selectionChanged() }
                    .padding(.horizontal, Theme.Metrics.spacingL)
                    // Reset the wheels when we switch stage so the re-entry
                    // starts from 00/00 like the view model intends.
                    .id(viewModel.stage)

                errorText

                VStack(spacing: Theme.Metrics.spacingM) {
                    Button {
                        viewModel.confirm()
                    } label: {
                        Label(viewModel.stage == .choose ? "Set Duration" : "Confirm", systemImage: viewModel.stage == .choose ? "timer" : "checkmark")
                    }
                    .buttonStyle(.tlPrimary)
                    .disabled(!viewModel.canConfirm)
                    .opacity(viewModel.canConfirm ? 1 : 0.45)
                    .accessibilityIdentifier(A11y.setupConfirmButton)

                    if viewModel.stage == .verify {
                        Button("Go Back") {
                            viewModel.goBack()
                        }
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Metrics.spacingXL)

                Text(viewModel.footnoteText)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Metrics.spacingXL)

                Spacer()
            }
        }
        .accessibilityIdentifier(A11y.setupScreen)
    }

    private var errorText: some View {
        Group {
            if let message = viewModel.errorMessage {
                Text(message)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Metrics.spacingXL)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
    }
}
