import UIKit

/// Central haptics gateway so the "Haptic feedback" setting is honored in one
/// place instead of at every call site.
final class HapticsService {
    static let shared = HapticsService()

    /// Set by AppState from user settings. Defaults on.
    var isEnabled: Bool = true

    private init() {}

    func selectionTick() {
        guard isEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    func light() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    func medium() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    func success() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Used for failed authentication. Deliberately identical in feel to a
    /// timer-confirmation tap so the reaction to a wrong duration carries no
    /// information about the secret.
    func error() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}
