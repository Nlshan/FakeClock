import LocalAuthentication
import UIKit

/// Outcome of a biometric attempt, mapped to user-facing copy by callers.
enum BiometricOutcome: Equatable {
    case success
    case userCancelled
    case notAvailable
    case failed
    case lockout
}

/// Wraps `LAContext` for optional Face ID / Touch ID unlock.
///
/// Biometric success grants a *session*, never replaces or modifies the
/// timer-duration credential: the secret stays in the Keychain untouched, so
/// turning Face ID off (or losing it) always falls back to duration unlock.
@MainActor
final class BiometricService {
    /// Availability of biometrics on this device. `.none` hides the toggle.
    enum Availability: Equatable {
        case faceID
        case touchID
        case unavailable
        case unsupported

        var label: String {
            switch self {
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .unavailable: return "Not Enrolled"
            case .unsupported: return "Not Supported"
            }
        }

        var systemImage: String {
            switch self {
            case .faceID: return "faceid"
            case .touchID: return "touchid"
            case .unavailable: return "questionmark.circle"
            case .unsupported: return "iphone.slash"
            }
        }

        /// True when a prompt can actually be presented right now.
        var isUsable: Bool {
            self == .faceID || self == .touchID
        }
    }

    private let contextProvider: () -> LAContext

    /// `contextProvider` is injectable so tests can stub availability and
    /// errors; `LAContext` itself cannot be meaningfully faked on iOS.
    init(contextProvider: @escaping () -> LAContext = LAContext.init) {
        self.contextProvider = contextProvider
    }

    /// Reports hardware capability separately from enrollment state so the
    /// Settings row can explain *why* Face ID can't be switched on.
    var availability: Availability {
        let context = contextProvider()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        switch context.biometryType {
        case .faceID:
            return canEvaluate ? .faceID : .unavailable
        case .touchID:
            return canEvaluate ? .touchID : .unavailable
        case .none:
            return .unsupported
        @unknown default:
            return .unsupported
        }
    }

    /// Attempts biometric unlock. The reason string names the app, not the
    /// secret, and never appears on the lock screen's failure path.
    func authenticate(reason: String) async -> BiometricOutcome {
        let context = contextProvider()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .notAvailable
        }
        do {
            let granted = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return granted ? .success : .failed
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel, .systemCancel, .appCancel:
                return .userCancelled
            case .biometryLockout, .passcodeNotSet:
                return .lockout
            case .biometryNotAvailable, .biometryNotEnrolled:
                return .notAvailable
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }
}
