import Foundation

/// Pure stopwatch state machine (§7).
///
/// Elapsed time is always recomputed as `now - legStart` plus any accumulated
/// time from previous legs, using a monotonic clock reading. Nothing is ever
/// incremented by a UI tick, which is why the stopwatch remains accurate after
/// backgrounding, suspension, or a device clock change.
///
/// `clock` is injected so tests advance time deterministically.
struct StopwatchEngine {
    enum Phase: Equatable {
        case idle
        case running
        case paused
    }

    struct Lap: Identifiable, Equatable {
        /// 1-based lap number as displayed.
        let number: Int
        /// Total elapsed at the moment the lap was taken.
        let total: TimeInterval
        /// Duration of this lap alone.
        let duration: TimeInterval
        /// `thisLapTotal - previousLapTotal`, i.e. split from the last lap.
        let difference: TimeInterval

        var id: Int { number }
    }

    enum LapFlag: Equatable {
        case fastest
        case slowest
        case none
    }

    private let clock: MonotonicClock

    private(set) var phase: Phase = .idle
    private(set) var accumulated: TimeInterval = 0
    private(set) var legStart: TimeInterval?
    private(set) var lapMarkTotals: [TimeInterval] = []

    init(clock: MonotonicClock = SystemClock.shared) {
        self.clock = clock
    }

    // MARK: Derived state

    /// Elapsed seconds, recomputed from timestamps on every call.
    func elapsed() -> TimeInterval {
        guard phase == .running, let legStart else { return accumulated }
        // `max(0,)` guards a restored snapshot whose leg start came from a
        // different process and therefore a different clock anchor.
        return accumulated + max(0, clock.reading() - legStart)
    }

    var laps: [Lap] {
        var result: [Lap] = []
        result.reserveCapacity(lapMarkTotals.count)
        var previous: TimeInterval = 0
        for (index, total) in lapMarkTotals.enumerated() {
            let duration = max(0, total - previous)
            result.append(
                Lap(
                    number: index + 1,
                    total: total,
                    duration: duration,
                    difference: duration
                )
            )
            previous = total
        }
        return result
    }

    /// Marks the fastest/slowest completed lap. Fewer than two laps returns
    /// `.none` throughout so the UI never labels a single lap as "fastest".
    func flag(for lapNumber: Int) -> LapFlag {
        let durations = laps.map(\.duration)
        guard durations.count >= 2 else { return .none }
        let index = lapNumber - 1
        guard durations.indices.contains(index) else { return .none }
        let fastest = durations.enumerated().min { $0.element < $1.element }?.offset
        let slowest = durations.enumerated().max { $0.element < $1.element }?.offset
        if index == fastest { return .fastest }
        if index == slowest { return .slowest }
        return .none
    }

    var canStart: Bool { phase == .idle }
    var canPause: Bool { phase == .running }
    var canReset: Bool { phase != .idle }
    var canAddLap: Bool { phase == .running }

    // MARK: Transitions

    /// Starts from zero.
    mutating func start() {
        accumulated = 0
        lapMarkTotals = []
        legStart = clock.reading()
        phase = .running
    }

    /// Pauses, folding the current leg into `accumulated`.
    mutating func pause() {
        guard phase == .running else { return }
        accumulated = elapsed()
        legStart = nil
        phase = .paused
    }

    /// Resumes without touching accumulated time.
    mutating func resume() {
        guard phase == .paused else { return }
        legStart = clock.reading()
        phase = .running
    }

    /// Back to a clean idle state.
    mutating func reset() {
        phase = .idle
        accumulated = 0
        legStart = nil
        lapMarkTotals = []
    }

    /// Records the current total elapsed as a lap. Only valid while running.
    @discardableResult
    mutating func addLap() -> Bool {
        guard phase == .running else { return false }
        lapMarkTotals.append(elapsed())
        return true
    }

    /// Snapshot for persistence.
    var session: StopwatchSession {
        StopwatchSession(
            phase: {
                switch phase {
                case .idle: return .idle
                case .running: return .running
                case .paused: return .paused
                }
            }(),
            accumulated: accumulated,
            legStartReading: legStart,
            lapMarkReadings: lapMarkTotals
        )
    }

    /// Restores a persisted session.
    ///
    /// `TimerLockViewModel` pauses the stopwatch before snapshotting when the
    /// app resigns active, so a `.running` snapshot only ever survives a hard
    /// termination (crash / swipe-kill). Monotonic anchors differ between
    /// processes, so the open leg cannot be measured after relaunch: the
    /// session is restored `.paused` at its last folded total rather than
    /// guessing the missing time. This is the truthful fallback (§7, §16) and
    /// is documented in the README's limitations section.
    init(clock: MonotonicClock = SystemClock.shared, session: StopwatchSession) {
        self.clock = clock
        self.accumulated = max(0, session.accumulated)
        self.lapMarkTotals = session.lapMarkReadings
        switch session.phase {
        case .idle:
            self.phase = .idle
        case .paused, .running:
            self.phase = .paused
        }
        self.legStart = nil
    }

    init(clock: MonotonicClock) {
        self.clock = clock
    }
}
