import SwiftUI

/// Drives first-run credential creation (§9.1) and the in-Settings rotation
/// flow (§13 "Change secret duration"), which share the same two-stage
/// "choose, then re-enter to verify" discipline.
///
/// Stage 1 — `choose`: the user selects a non-zero duration and confirms it is
/// valid. Stage 2 — `verify`: the same wheels are reset to 00/00 and the user
/// must re-enter the identical value. Only after both agree is the secret
/// written to the Keychain and setup marked complete.
///
/// The resulting `totalMinutes` is never displayed anywhere (§9.1).
@MainActor
final class SetupAuthenticationViewModel: ObservableObject {
    enum Stage: Equatable {
        case choose
        case verify
    }

    /// Which credential path this flow writes.
    enum Mode {
        /// First run: no credential exists, so setup is finalized afterwards.
        case initialSetup
        /// Already authenticated: rotate the secret, keeping the old one live
        /// until the re-entry matches (so a cancelled rotation never locks the
        /// user out).
        case rotation
    }

    let mode: Mode

    @Published var hours: Int = 0
    @Published var minutes: Int = 0
    @Published var stage: Stage = .choose
    /// User-facing, non-secret problem text (range, zero, mismatch).
    @Published var errorMessage: String?
    /// True when both entries matched and the secret is stored.
    @Published private(set) var isComplete = false

    /// Chosen value held between stages. Kept private so no view can render
    /// it; it is also never the raw stored form — only `totalMinutes` is.
    private var chosen: (hours: Int, minutes: Int)?

    private let authManager: AuthenticationManager
    private let lockManager: LockManager
    private let onFinish: (() -> Void)?

    init(
        authManager: AuthenticationManager,
        lockManager: LockManager,
        mode: Mode = .initialSetup,
        onFinish: (() -> Void)? = nil
    ) {
        self.authManager = authManager
        self.lockManager = lockManager
        self.mode = mode
        self.onFinish = onFinish
    }

    /// Zero duration disables the primary button, so the invalid path cannot
    /// even be tapped (§9.1).
    var canConfirm: Bool {
        AuthenticationManager.isValidDuration(hours: hours, minutes: minutes)
    }

    var instructionText: String {
        switch stage {
        case .choose:
            return "Set a secret duration"
        case .verify:
            return "Enter it again to confirm"
        }
    }

    var footnoteText: String {
        switch stage {
        case .choose:
            return "This duration is how you unlock Timer Lock. It is stored only in the device Keychain."
        case .verify:
            return "Choose the same hours and minutes you just set."
        }
    }

    // MARK: Actions

    func confirm() {
        errorMessage = nil
        switch stage {
        case .choose:
            acceptFirstChoice()
        case .verify:
            completeVerification()
        }
    }

    func selectionChanged() {
        if errorMessage != nil {
            errorMessage = nil
        }
        HapticsService.shared.selectionTick()
    }

    /// Back from verify to choose, preserving the original selection so the
    /// user can correct a mis-remembered re-entry rather than start over.
    func goBack() {
        guard stage == .verify, let chosen else { return }
        stage = .choose
        hours = chosen.hours
        minutes = chosen.minutes
        errorMessage = nil
    }

    /// Abandons an in-progress rotation without touching the live secret.
    func cancel() {
        authManager.cancelRotation()
        chosen = nil
    }

    // MARK: Stage logic

    private func acceptFirstChoice() {
        guard AuthenticationManager.isValidDuration(hours: hours, minutes: minutes) else {
            errorMessage = errorMessageForInvalid()
            HapticsService.shared.error()
            return
        }
        chosen = (hours, minutes)
        stage = .verify
        // Wheels reset so the confirm step is a genuine re-entry, not a tap.
        hours = 0
        minutes = 0
        HapticsService.shared.medium()
    }

    private func completeVerification() {
        guard let chosen else {
            stage = .choose
            return
        }
        guard AuthenticationManager.isValidDuration(hours: hours, minutes: minutes) else {
            errorMessage = errorMessageForInvalid()
            HapticsService.shared.error()
            return
        }

        do {
            switch mode {
            case .rotation:
                // Reached from Settings while unlocked. The staged rotation API
                // keeps the old secret live until the re-entry matches, so a
                // cancelled or mismatched rotation never locks the user out.
                try authManager.beginRotation(hours: chosen.hours, minutes: chosen.minutes)
                try authManager.confirmRotation(confirmHours: hours, minutes: minutes)
            case .initialSetup:
                try authManager.completeSetup(
                    chosenHours: chosen.hours,
                    chosenMinutes: chosen.minutes,
                    confirmHours: hours,
                    confirmMinutes: minutes
                )
            }
            isComplete = true
            HapticsService.shared.success()
            onFinish?()
        } catch let error as AuthSetupError {
            errorMessage = error.errorDescription
            HapticsService.shared.error()
            if case .confirmationMismatch = error {
                // Restart cleanly at the choose stage.
                stage = .choose
                hours = chosen.hours
                minutes = chosen.minutes
            }
        } catch {
            errorMessage = AuthSetupError.keychainFailure("").errorDescription
            HapticsService.shared.error()
        }
    }

    private func errorMessageForInvalid() -> String {
        if hours == 0 && minutes == 0 {
            return AuthSetupError.zeroDuration.errorDescription ?? "Choose a duration."
        }
        return AuthSetupError.invalidRange.errorDescription ?? "Invalid duration."
    }
}
