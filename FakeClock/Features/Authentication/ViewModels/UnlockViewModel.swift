import SwiftUI

/// Drives the authentication screen (§9.2).
///
/// The view model exposes only an `isAuthenticated` latch and one generic
/// failure string. It never surfaces the stored duration, distance-to-correct
/// hints, or attempt counters (§9.2: error messages must not reveal the
/// credential).
@MainActor
final class UnlockViewModel: ObservableObject {
    @Published var hours: Int = 0
    @Published var minutes: Int = 0
    /// Generic failure copy, cleared as soon as the wheels move again.
    @Published var failureMessage: String?
    /// True after a successful unlock; the root gate observes this.
    @Published private(set) var isAuthenticated = false
    /// Guards against double submits while a biometric prompt runs.
    @Published private(set) var isBiometricPending = false
    /// Present the credential-missing recovery UI instead of a dead lock.
    @Published private(set) var needsRecovery: Bool

    private let authManager: AuthenticationManager
    private let lockManager: LockManager
    private let biometrics: BiometricService
    private let settingsProvider: () -> AppSettings

    init(
        authManager: AuthenticationManager,
        lockManager: LockManager,
        biometrics: BiometricService,
        settingsProvider: @escaping () -> AppSettings
    ) {
        self.authManager = authManager
        self.lockManager = lockManager
        self.biometrics = biometrics
        self.settingsProvider = settingsProvider
        self.needsRecovery = authManager.isCredentialMissing
    }

    /// Zero duration is rejected up-front so the confirm button cannot submit
    /// a value that could never have been saved (§9.1 constraints).
    var canSubmit: Bool {
        !isBiometricPending && AuthenticationManager.isValidDuration(hours: hours, minutes: minutes)
    }

    /// Biometric row shows only when the user enabled it AND the hardware can
    /// actually evaluate; otherwise the duration path is the only door.
    var showsBiometricOption: Bool {
        settingsProvider().biometricEnabled && biometrics.availability.isUsable
    }

    var biometricLabel: String {
        biometrics.availability.label
    }

    // MARK: Actions

    /// Steps (§9.2): validate → totalMinutes → read stored secret → compare →
    /// unlock only on an exact match.
    func submit() {
        failureMessage = nil
        guard AuthenticationManager.isValidDuration(hours: hours, minutes: minutes) else {
            reportFailure()
            return
        }
        let result: AuthResult
        do {
            result = try authManager.verify(hours: hours, minutes: minutes)
        } catch {
            // Any Keychain error folds into the same generic failure so
            // storage state is never revealed (§9.3, §18).
            reportFailure()
            return
        }
        switch result {
        case .success:
            isAuthenticated = true
            lockManager.unlock()
            HapticsService.shared.success()
        case .invalidDuration:
            reportFailure()
        }
    }

    /// Wheel `onChange`: clears a stale warning and ticks.
    func selectionChanged() {
        if failureMessage != nil {
            failureMessage = nil
        }
        HapticsService.shared.selectionTick()
    }

    func attemptBiometric() async {
        guard settingsProvider().biometricEnabled, !isBiometricPending else { return }
        isBiometricPending = true
        lockManager.beginBiometricPrompt()
        defer {
            isBiometricPending = false
            lockManager.endBiometricPrompt()
        }

        let outcome = await biometrics.authenticate(reason: "Unlock Timer Lock")
        switch outcome {
        case .success:
            isAuthenticated = true
            lockManager.unlock()
            failureMessage = nil
        case .userCancelled:
            // Silent: backing out of the system sheet is not a failed attempt.
            break
        case .notAvailable:
            failureMessage = "Face ID is unavailable. Enter your duration instead."
        case .lockout:
            failureMessage = "Biometric locked out. Enter your duration to continue."
        case .failed:
            reportFailure()
        }
    }

    /// Recovery from a lost/corrupt credential (§18): deletes the broken
    /// secret + sentinel, returning the app to first-run setup.
    func resetAndRecover() {
        do {
            try lockManager.resetCredential()
            needsRecovery = false
        } catch {
            failureMessage = "Could not reset secure storage. Try again."
        }
    }

    private func reportFailure() {
        failureMessage = "Duration does not match. Try again."
        HapticsService.shared.error()
    }
}
