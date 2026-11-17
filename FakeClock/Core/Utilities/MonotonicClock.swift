import Foundation

/// Abstraction over a monotonic time source.
///
/// Timing features ask *this* for a reading instead of advancing a counter
/// with `Timer` — the technique that lets the stopwatch stay accurate across
/// backgrounding and suspension (§7) and that keeps every engine testable
/// with a controllable clock.
protocol MonotonicClock: Sendable {
    /// Seconds since an arbitrary process-fixed reference. Only differences
    /// between two readings are meaningful.
    func reading() -> TimeInterval
}

/// Production clock backed by `ContinuousClock` (iOS 16+).
///
/// `ContinuousClock` is monotonic: it is unaffected by the user changing the
/// wall clock, and on Darwin it keeps advancing while the app is suspended,
/// so `reading()` deltas match real elapsed time. The reference instant is
/// captured at init and stays fixed for the process lifetime, which makes
/// every reading a duration from that anchor.
struct SystemClock: MonotonicClock {
    static let shared = SystemClock()

    private let clock = ContinuousClock()
    /// Per-process anchor. Durations are measured from this instant so
    /// readings grow monotonically without absolute meaning.
    let anchor: ContinuousClock.Instant

    init() {
        anchor = clock.now
    }

    func reading() -> TimeInterval {
        let elapsed = clock.measure(from: anchor, to: clock.now)
        let components = elapsed.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// Controllable clock for unit tests.
final class TestClock: MonotonicClock, @unchecked Sendable {
    private(set) var value: TimeInterval
    private let lock = NSLock()

    init(startingAt value: TimeInterval = 0) {
        self.value = value
    }

    func reading() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    /// Advances the clock as if wall time had passed.
    func advance(by seconds: TimeInterval) {
        lock.lock()
        value += seconds
        lock.unlock()
    }

    func set(_ newValue: TimeInterval) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}
