import Foundation
import SwiftUI

/// Locked / unlocked state of the application's own content, plus the rules
/// that decide when it must relock (§10, §11).
///
/// This protects the contents of **Timer Lock** only. A normal third-party
/// iOS app cannot lock other applications or override iOS security, and this
/// class makes no such claim (spec §10).
@MainActor
final class LockManager {
    enum LockState: Equatable {
        /// No credential exists yet — first-run setup is shown.
        case needsSetup
        /// A credential exists and the app must be authenticated.
        case locked
        /// Authenticated for this session.
        case unlocked
    }

    private(set) var state: LockState = .needsSetup

    /// True while a biometric prompt is in flight, so the unlock view does not
    /// present a second simultaneous prompt.
    private(set) var isBiometricPromptActive = false

    /// Wall-clock time the app last entered the background. Cleared on return.
    private(set) var lastBackgrounded: Date?

    private let authManager: AuthenticationManager
    private let now: () -> Date

    /// Live settings reader, assigned by the composition root after the
    /// settings store exists. Mutable so the policy can change at runtime
    /// without rebuilding the manager.
    var settingsProvider: () -> AppSettings = { AppSettings.default }

    /// `now` is injectable so relock timing is unit-testable without sleeping.
    init(
        authManager: AuthenticationManager,
        now: @escaping () -> Date = Date.init
    ) {
        self.authManager = authManager
        self.now = now
    }

    var isUnlocked: Bool { state == .unlocked }
    /// True when protected content must not be shown.
    var requiresAuthentication: Bool { state != .unlocked }

    // MARK: State transitions

    /// Decides the initial state at launch. Called synchronously before the
    /// root view body evaluates, so protected content can never flash (§10).
    func restoreInitialState() {
        state = authManager.isSetupComplete ? .locked : .needsSetup
    }

    /// Called by the setup view model after a successful save: the user has
    /// just proven knowledge of the new credential, so the session opens.
    func finishSetupAndUnlock() {
        state = .unlocked
        lastBackgrounded = nil
    }

    /// Called after a verified duration or a successful biometric check.
    func unlock() {
        state = .unlocked
        lastBackgrounded = nil
    }

    /// Manual lock, and the target state for every relock rule.
    func lock() {
        guard state == .unlocked else { return }
        state = .locked
    }

    func beginBiometricPrompt() { isBiometricPromptActive = true }
    func endBiometricPrompt() { isBiometricPromptActive = false }

    // MARK: Lifecycle (spec §11)

    /// Handles a `ScenePhase` transition.
    func handlePhase(_ phase: ScenePhase, at date: Date? = nil) {
        let moment = date ?? now()
        switch phase {
        case .active:
            defer { lastBackgrounded = nil }
            // Only relock if we came back from a real background stint.
            if lastBackgrounded != nil, shouldRelockOnReturn(at: moment) {
                lock()
            }
        case .background:
            lastBackgrounded = moment
            if settingsProvider().relockPolicy == .immediatelyOnBackground {
                lock()
            }
        case .inactive:
            // iOS also reports `.inactive` for Control Center, notification
            // shadings and system alerts. Locking there would be hostile and
            // would not improve security, so we deliberately ignore it.
            // Device-lock is not directly observable by a third-party app;
            // the `.background` transition is the legitimate signal (§11).
            break
        @unknown default:
            break
        }
    }

    /// Whether returning to the foreground must relock, under the current
    /// policy and the elapsed background duration. Pure: tests drive it
    /// directly with explicit dates.
    func shouldRelockOnReturn(at date: Date? = nil) -> Bool {
        guard state == .unlocked, let backgrounded = lastBackgrounded else { return false }
        let moment = date ?? now()
        switch settingsProvider().relockPolicy {
        case .immediatelyOnBackground:
            return true
        case .afterShortDelay:
            return moment.timeIntervalSince(backgrounded) >= 60
        case .manualOnly:
            return false
        }
    }

    // MARK: Recovery

    /// Clears the credential and the setup sentinel, returning the app to
    /// first-run setup. Reached only from Settings (inside the unlocked shell)
    /// or from the credential-missing recovery screen (§18).
    func resetCredential() throws {
        try authManager.resetAllData()
        lastBackgrounded = nil
        state = .needsSetup
    }

    /// Whether setup completed but the secret is unreadable.
    var needsCredentialRecovery: Bool {
        authManager.isCredentialMissing
    }
}
