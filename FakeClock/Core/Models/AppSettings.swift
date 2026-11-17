import SwiftUI

/// When the app must relock itself.
enum RelockPolicy: String, CaseIterable, Identifiable, Codable {
    /// Lock as soon as the app leaves the foreground.
    case immediatelyOnBackground
    /// Lock after a grace period of backgrounding/inactivity.
    case afterShortDelay
    /// Lock only when the device itself has been unlocked-and-rellocked, or on
    /// manual lock. Weakest policy; offered explicitly.
    case manualOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .immediatelyOnBackground: return "Immediately"
        case .afterShortDelay: return "After 1 minute"
        case .manualOnly: return "Manually only"
        }
    }

    var detail: String {
        switch self {
        case .immediatelyOnBackground:
            return "Require your duration every time Timer Lock leaves the foreground."
        case .afterShortDelay:
            return "Stay unlocked for one minute, then require your duration."
        case .manualOnly:
            return "Stay unlocked until you lock it yourself. Least secure."
        }
    }

    /// Seconds of background/inactivity tolerance before relocking.
    var graceInterval: TimeInterval {
        switch self {
        case .immediatelyOnBackground: return 0
        case .afterShortDelay: return 60
        case .manualOnly: return .infinity
        }
    }
}

/// Interface appearance preference.
enum AppAppearance: String, CaseIterable, Identifiable, Codable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }

    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

/// Non-secret user preferences, persisted as JSON in `UserDefaults`.
///
/// `equatable` conformance matters: AppState uses value comparison to avoid
/// republishing and re-rendering the whole tree on every tick.
struct AppSettings: Codable, Equatable {
    var relockPolicy: RelockPolicy = .immediatelyOnBackground
    var biometricEnabled: Bool = false
    var hapticsEnabled: Bool = true
    var appearance: AppAppearance = .dark
    /// Audible alert played when a countdown completes (in-app and, where the
    /// OS permits, in the completion notification).
    var timerCompletionSound: AlertSound = .default
    /// Whether the World Clock header shows 24-hour or 12-hour time locally.
    var use24HourClock: Bool = false

    static let `default` = AppSettings()
}

/// Audible alert choices for timer completion and alarms. The model stays
/// framework-pure; `SoundService` maps each choice onto an iOS system sound
/// identifier, and `NotificationPlan` decides whether the notification itself
/// carries sound. This avoids bundling audio assets and avoids a
/// MediaPlayer/audio-session dependency.
///
/// iOS 16 exposes no public per-alarm ringtone picker without private APIs, so
/// a set of system tones is the best legitimate native alternative. The
/// limitation is documented in README "Known iOS limitations".
enum AlertSound: String, CaseIterable, Identifiable, Codable {
    case reflex
    case bell
    case chime
    case none

    var id: String { rawValue }

    static let `default` = AlertSound.chime

    var label: String {
        switch self {
        case .reflex: return "Reflex"
        case .bell: return "Bell"
        case .chime: return "Chime"
        case .none: return "Silent"
        }
    }

    var detail: String {
        switch self {
        case .none: return "Vibration and visual alert only"
        default: return "System tone"
        }
    }

    /// False only for `.none`; used to skip both in-app playback and
    /// notification sound.
    var playsSound: Bool { self != .none }
}
