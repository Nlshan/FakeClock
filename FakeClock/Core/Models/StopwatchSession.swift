import Foundation

/// Durable stopwatch state.
///
/// Only accumulated monotonic readings are persisted — the stopwatch never
/// stores a counter it increments itself (§7).
struct StopwatchSession: Codable, Equatable {
    enum Phase: String, Codable {
        case idle
        case running
        case paused
    }

    var phase: Phase = .idle
    /// Accumulated elapsed seconds, not counting the current run leg.
    var accumulated: TimeInterval = 0
    /// Monotonic reading captured when the current leg started.
    var legStartReading: TimeInterval?
    /// Laps recorded, oldest first. Each value is the total elapsed time at
    /// the moment the lap was taken, so lap durations derive by subtraction.
    var lapMarkReadings: [TimeInterval] = []

    static let empty = StopwatchSession()

    /// Elapsed seconds at `nowReading` of the monotonic clock.
    func elapsed(nowReading: TimeInterval) -> TimeInterval {
        let leg: TimeInterval
        switch phase {
        case .idle, .paused:
            leg = 0
        case .running:
            guard let start = legStartReading else { return accumulated }
            // Clamp: a restored snapshot from a previous process could have a
            // reading larger than the current one (different clock anchor).
            leg = max(0, nowReading - start)
        }
        return accumulated + leg
    }

    /// Total elapsed at each lap mark, oldest first.
    var lapTotals: [TimeInterval] {
        lapMarkReadings
    }

    /// Lap durations derived from consecutive marks (spec §7: recomputed from
    /// timestamps, never from an incrementing counter).
    func lapDurations() -> [TimeInterval] {
        var previous: TimeInterval = 0
        return lapMarkReadings.map { mark in
            let duration = max(0, mark - previous)
            previous = mark
            return duration
        }
    }

    /// Indices of the fastest and slowest completed laps, nil when there are
    /// fewer than two laps (so "fastest" is never shown alone as a claim).
    func extremeLapIndices() -> (fastest: Int?, slowest: Int?) {
        let durations = lapDurations()
        guard durations.count >= 2 else {
            if durations.count == 1 { return (fastest: 0, slowest: 0) }
            return (nil, nil)
        }
        var fastest = 0
        var slowest = 0
        for (index, value) in durations.enumerated() {
            if value < durations[fastest] { fastest = index }
            if value > durations[slowest] { slowest = index }
        }
        return (fastest, slowest)
    }
}
