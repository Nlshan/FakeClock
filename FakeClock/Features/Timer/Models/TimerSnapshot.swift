import Foundation

/// Durable snapshot of the countdown, written on every state change so a
/// relaunch or a foreground return can restore the exact remaining time from
/// an absolute deadline instead of a countdown counter (§8).
struct TimerSnapshot: Codable, Equatable {
    enum Phase: String, Codable {
        case idle
        case running
        case paused
        case finished
    }

    var phase: Phase = .idle
    /// Total duration the user configured, in seconds.
    var totalSeconds: TimeInterval = 0
    /// Absolute end instant while running. Remaining time is always derived
    /// from this and never decremented.
    var endDate: Date?
    /// Frozen remaining seconds while paused.
    var pausedRemaining: TimeInterval?
    /// Display label for the notification and the header.
    var label: String = "Timer"
    /// True once completion has been handled, so the completion event cannot
    /// fire twice after a background/foreground cycle (§8: no duplicates).
    var hasFired: Bool = false

    static let empty = TimerSnapshot()

    /// Remaining seconds at `now` for the running phase, clamped at zero.
    func remainingSeconds(now: Date) -> TimeInterval {
        switch phase {
        case .idle:
            return 0
        case .running:
            guard let endDate else { return 0 }
            return max(0, endDate.timeIntervalSince(now))
        case .paused:
            return max(0, pausedRemaining ?? 0)
        case .finished:
            return 0
        }
    }

    /// Fraction elapsed, 0…1. Zero progress for an idle or empty timer.
    func progress(now: Date) -> Double {
        guard totalSeconds > 0 else { return 0 }
        let remaining = remainingSeconds(now: now)
        return min(1, max(0, 1 - remaining / totalSeconds))
    }
}
