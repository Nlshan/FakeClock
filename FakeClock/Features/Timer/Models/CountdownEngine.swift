import Foundation

/// Pure countdown state machine (§8).
///
/// Design invariants, all covered by `CountdownEngineTests`:
///  - Remaining time is *always* derived from an absolute end date, never by
///    decrementing a counter. `Timer`/display-link ticks only choose when to
///    re-read the clock, so backgrounding and suspension cannot cause drift.
///  - A completion is emitted at most once per run (`hasFired` latch), so a
///    return from background cannot fire a duplicate event.
///  - Zero-duration and invalid inputs are rejected at the boundary, so no
///    invalid internal state is reachable.
///
/// The engine is synchronous and value-typed; `TimerViewModel` owns one and
/// drives its ticks, which keeps the rules independent of SwiftUI.
struct CountdownEngine {
    enum Phase: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    struct Input: Equatable {
        var hours: Int
        var minutes: Int
        var seconds: Int

        var totalSeconds: TimeInterval {
            TimeInterval(hours * 3600 + minutes * 60 + seconds)
        }

        static let zero = Input(hours: 0, minutes: 0, seconds: 0)

        /// Every component must sit in its natural range and the total must be
        /// positive: zero-length countdowns and out-of-range picker values are
        /// invalid (§8 "handle zero-duration input / prevent invalid states").
        var isValid: Bool {
            (0...23).contains(hours) && (0...59).contains(minutes) && (0...59).contains(seconds) && totalSeconds > 0
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var totalSeconds: TimeInterval = 0
    private(set) var endDate: Date?
    private(set) var pausedRemaining: TimeInterval = 0
    private(set) var hasFired = false
    var label: String = "Timer"

    init() {}

    // MARK: Derived state

    /// Remaining time at `now`. Clamped to zero.
    func remainingSeconds(now: Date) -> TimeInterval {
        switch phase {
        case .idle:
            return 0
        case .running:
            guard let endDate else { return 0 }
            return max(0, endDate.timeIntervalSince(now))
        case .paused:
            return max(0, pausedRemaining)
        case .finished:
            return 0
        }
    }

    /// Convenience overload reading the wall clock.
    func remainingSeconds() -> TimeInterval {
        remainingSeconds(now: Date())
    }

    /// Elapsed fraction 0…1 for the circular progress ring.
    func progress(now: Date) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - remainingSeconds(now: now) / totalSeconds))
    }

    var canStart: Bool {
        phase == .idle || phase == .finished
    }

    var canPause: Bool { phase == .running }
    var canResume: Bool { phase == .paused }

    // MARK: Transitions

    /// Configures and starts a countdown. Returns false for invalid input,
    /// leaving the previous state untouched.
    @discardableResult
    mutating func start(_ input: Input, now: Date) -> Bool {
        guard input.isValid else { return false }
        totalSeconds = input.totalSeconds
        endDate = now.addingTimeInterval(input.totalSeconds)
        pausedRemaining = 0
        hasFired = false
        phase = .running
        return true
    }

    /// Starts from an already-validated duration (used by the quick presets).
    @discardableResult
    mutating func start(seconds: TimeInterval, now: Date) -> Bool {
        guard seconds > 0 else { return false }
        let floored = seconds.rounded()
        let hours = Int(floored) / 3600
        let minutes = (Int(floored) % 3600) / 60
        let secs = Int(floored) % 60
        return start(Input(hours: hours, minutes: minutes, seconds: secs), now: now)
    }

    /// Freezes the remaining time. No-op unless running.
    mutating func pause(now: Date) {
        guard phase == .running else { return }
        pausedRemaining = remainingSeconds(now: now)
        endDate = nil
        phase = .paused
    }

    /// Resumes from a pause by recomputing the end date from *current* time,
    /// so time spent paused is never counted.
    mutating func resume(now: Date) {
        guard phase == .paused, pausedRemaining > 0 else { return }
        endDate = now.addingTimeInterval(pausedRemaining)
        phase = .running
    }

    /// Stops and clears everything back to the empty idle state.
    mutating func cancel() {
        phase = .idle
        totalSeconds = 0
        endDate = nil
        pausedRemaining = 0
        hasFired = false
    }

    /// Alias for cancel; kept explicit because the UI offers both "Cancel"
    /// (running) and "Reset" (finished/paused) affordances.
    mutating func reset() {
        cancel()
    }

    /// Called on every tick. Detects completion and returns true exactly once
    /// per run so the caller can play the sound / post the notification
    /// without duplicate events (§8).
    @discardableResult
    mutating func tick(now: Date) -> Bool {
        guard phase == .running, let endDate else { return false }
        guard now >= endDate else { return false }
        phase = .finished
        pausedRemaining = 0
        if hasFired { return false }
        hasFired = true
        return true
    }

    /// True when the deadline has passed while the app was away, so the view
    /// model can restore completion without re-notifying.
    func isOverdue(now: Date) -> Bool {
        phase == .running && (endDate.map { now >= $0 } ?? false)
    }

    // MARK: Persistence bridge

    var snapshot: TimerSnapshot {
        TimerSnapshot(
            phase: {
                switch phase {
                case .idle: return .idle
                case .running: return .running
                case .paused: return .paused
                case .finished: return .finished
                }
            }(),
            totalSeconds: totalSeconds,
            endDate: endDate,
            pausedRemaining: phase == .paused ? pausedRemaining : nil,
            label: label,
            hasFired: hasFired
        )
    }

    /// Restores a snapshot. A running snapshot whose deadline already passed is
    /// restored as `finished` with `hasFired` preserved, so the completion the
    /// notification already delivered is not repeated on launch.
    init(snapshot: TimerSnapshot, now: Date) {
        self.label = snapshot.label
        self.totalSeconds = snapshot.totalSeconds
        self.hasFired = snapshot.hasFired
        switch snapshot.phase {
        case .idle:
            self.phase = .idle
        case .running:
            if let endDate = snapshot.endDate {
                if now >= endDate {
                    self.phase = .finished
                    self.endDate = nil
                    self.pausedRemaining = 0
                } else {
                    self.phase = .running
                    self.endDate = endDate
                }
            } else {
                self.phase = .idle
            }
        case .paused:
            self.phase = .paused
            self.pausedRemaining = max(0, snapshot.pausedRemaining ?? 0)
        case .finished:
            self.phase = .finished
        }
    }
}
