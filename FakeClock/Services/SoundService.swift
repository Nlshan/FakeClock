import AudioToolbox
import Foundation

/// Plays short completion tones using iOS system sounds.
///
/// Using `AudioServicesPlaySystemSound` (rather than `AVAudioPlayer` or
/// `MPMusicPlayerController`) means no audio-session category fighting with
/// the user's music and no third-party dependency. iOS 16 offers no public
/// per-alarm ringtone picker without private APIs, so this is the best
/// legitimate native alternative for in-app completion feedback; the
/// notification path is documented in `NotificationService`.
struct SoundService {
    /// System sound identifiers chosen from tones available on every device
    /// without shipping assets. These are stable public iOS system sounds.
    static func systemSoundID(for sound: AlertSound) -> SystemSoundID? {
        switch sound {
        case .reflex: return 1155
        case .bell: return 1104
        case .chime: return 1154
        case .none: return nil
        }
    }

    /// Plays the configured tone immediately (foreground completion).
    static func play(_ sound: AlertSound) {
        guard let id = systemSoundID(for: sound) else { return }
        AudioServicesPlaySystemSound(id)
    }
}
