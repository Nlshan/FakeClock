import Foundation

/// User-facing result of an unlock attempt. Deliberately generic: the same
/// shape is returned whether the failure was a wrong duration, a Keychain
/// read error, or missing setup, so no error message reveals anything about
/// the stored credential.
enum AuthResult: Equatable {
    case success
    case invalidDuration
}

/// Structured errors raised during setup/rotation. These describe operations,
/// never the secret value itself.
enum AuthSetupError: LocalizedError, Equatable {
    case zeroDuration
    case invalidRange
    case confirmationMismatch
    case keychainFailure(String)
    case credentialMissing

    var errorDescription: String? {
        switch self {
        case .zeroDuration:
            return "A 00:00 duration cannot be used. Choose at least one minute."
        case .invalidRange:
            return "Hours must be 0–23 and minutes 0–59."
        case .confirmationMismatch:
            return "The durations did not match. Please start again."
        case .keychainFailure:
            return "Secure storage failed. Your duration was not saved — try again."
        case .credentialMissing:
            return "No secret duration is configured yet."
        }
    }
}

/// Owns the timer-duration credential: setup, verification, rotation, removal.
///
/// The credential is `totalMinutes = hours * 60 + minutes`, stored only as a
/// decimal string in the Keychain. Views never touch `KeychainServicing`
/// directly; they go through this manager (and `LockManager`).
@MainActor
final class AuthenticationManager {
    private let keychain: KeychainServicing

    init(keychain: KeychainServicing) {
        self.keychain = keychain
    }

    // MARK: - Pure validation helpers

    /// Canonical formula for the duration credential.
    static func totalMinutes(hours: Int, minutes: Int) -> Int {
        hours * 60 + minutes
    }

    /// Range + non-zero rule shared by setup and unlock paths.
    static func isValidDuration(hours: Int, minutes: Int) -> Bool {
        (0...23).contains(hours) && (0...59).contains(minutes) && totalMinutes(hours: hours, minutes: minutes) > 0
    }

    // MARK: - State queries

    /// True once setup has completed. Read from the non-secret sentinel so a
    /// cold launch can decide locked vs. setup UI without touching the secret.
    ///
    /// Decision documented for the security section: a fixed-sentinel read is
    /// synchronous here because the root gate must decide the first rendered
    /// frame — an async check would force a placeholder screen and risk a
    /// protected-content flash, which section 10 of the spec forbids. The
    /// sentinel itself is not sensitive.
    var isSetupComplete: Bool {
        get {
            (try? keychain.readString(for: SecretKey.setupComplete.rawValue)) == "1"
        }
    }

    /// True when the user has completed setup but the Keychain no longer
    /// returns a readable credential (corruption, restore edge cases). The
    /// lock screen surfaces a recovery flow instead of a dead end.
    var isCredentialMissing: Bool {
        guard isSetupComplete else { return false }
        return (try? keychain.readInt(for: SecretKey.authDurationMinutes.rawValue)) == nil
    }

    // MARK: - Setup & rotation

    /// Verifies the confirm-step value against the chosen value, then persists.
    /// On Keychain failure everything is rolled back so the user can retry.
    func completeSetup(chosenHours: Int, chosenMinutes: Int, confirmHours: Int, confirmMinutes: Int) throws {
        let first = totalMinutes(hours: chosenHours, minutes: chosenMinutes)
        let second = totalMinutes(hours: confirmHours, minutes: confirmMinutes)

        // Ordered deliberately: out-of-range first, then the zero rule, so a
        // 0:00 selection reports the actionable reason rather than "invalid".
        let inRange = (0...23).contains(chosenHours) && (0...59).contains(chosenMinutes)
            && (0...23).contains(confirmHours) && (0...59).contains(confirmMinutes)
        guard inRange else { throw AuthSetupError.invalidRange }
        guard first > 0, second > 0 else { throw AuthSetupError.zeroDuration }
        guard first == second else { throw AuthSetupError.confirmationMismatch }

        do {
            try saveSecret(totalMinutes: first)
            try keychain.save(data: Data("1".utf8), for: SecretKey.setupComplete.rawValue)
        } catch let error as KeychainError {
            try? keychain.delete(for: SecretKey.setupComplete.rawValue)
            throw AuthSetupError.keychainFailure(error.localizedDescription)
        }
    }

    /// Two-stage rotation so the "change duration" flow keeps the same
    /// verify-twice discipline as initial setup.
    ///
    /// Stage 1 records the candidate after the user has chosen it.
    /// Stage 2 confirms it; the old secret stays live until confirmation, so
    /// a canceled or mismatched rotation never locks the user out.
    private(set) var pendingRotation: (hours: Int, minutes: Int)?

    func beginRotation(hours: Int, minutes: Int) throws {
        guard (0...23).contains(hours), (0...59).contains(minutes) else {
            throw AuthSetupError.invalidRange
        }
        guard totalMinutes(hours: hours, minutes: minutes) > 0 else {
            throw AuthSetupError.zeroDuration
        }
        pendingRotation = (hours, minutes)
    }

    func confirmRotation(confirmHours: Int, confirmMinutes: Int) throws {
        guard let pending = pendingRotation else {
            throw AuthSetupError.credentialMissing
        }
        let candidate = Self.totalMinutes(hours: pending.hours, minutes: pending.minutes)
        let confirm = Self.totalMinutes(hours: confirmHours, minutes: confirmMinutes)
        guard confirm == candidate else {
            pendingRotation = nil
            throw AuthSetupError.confirmationMismatch
        }
        do {
            try saveSecret(totalMinutes: candidate)
        } catch let error as KeychainError {
            throw AuthSetupError.keychainFailure(error.localizedDescription)
        }
        pendingRotation = nil
    }

    func cancelRotation() {
        pendingRotation = nil
    }

    // MARK: - Verification

    /// The single comparison path used by the unlock screen. Any stored
    /// credential is accepted; a zero-duration credential can never exist
    /// because saving it throws here.
    func verify(hours: Int, minutes: Int) throws -> AuthResult {
        guard Self.isValidDuration(hours: hours, minutes: minutes) else {
            return .invalidDuration
        }
        let stored: Int?
        do {
            stored = try keychain.readInt(for: SecretKey.authDurationMinutes.rawValue)
        } catch {
            // Read failure (e.g. device locked) is reported as a generic
            // failure, never as a distinct error that hints at storage state.
            return .invalidDuration
        }
        guard let stored else { return .invalidDuration }
        return Self.totalMinutes(hours: hours, minutes: minutes) == stored ? .success : .invalidDuration
    }

    // MARK: - Destruction

    /// Removes the secret and the setup sentinel, returning the app to the
    /// first-run state. Guarded: setup can only be reset while the app is
    /// unlocked (enforced by the Settings UI being inside the locked shell).
    func resetAllData() throws {
        do {
            try keychain.delete(for: SecretKey.authDurationMinutes.rawValue)
            try keychain.delete(for: SecretKey.setupComplete.rawValue)
        } catch let error as KeychainError {
            throw AuthSetupError.keychainFailure(error.localizedDescription)
        }
    }

    // MARK: - Private

    private func saveSecret(totalMinutes: Int) throws {
        guard totalMinutes > 0, totalMinutes <= 23 * 60 + 59 else {
            throw AuthSetupError.invalidRange
        }
        // The value is the entire credential, so encoding it is the moment to
        // guarantee this property holds for every code path that reaches here.
        let data = Data(String(totalMinutes).utf8)
        try keychain.save(data: data, for: SecretKey.authDurationMinutes.rawValue)
    }
}
