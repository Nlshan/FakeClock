import Foundation

/// Weekday selection for repeating alarms. `rawValue` matches
/// `Calendar.component(.weekday, ...)`: Sunday = 1 … Saturday = 7.
enum Weekday: Int, CaseIterable, Identifiable, Codable, Sendable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7

    var id: Int { rawValue }
    var calendarIndex: Int { rawValue }

    var shortSymbol: String {
        switch self {
        case .sunday: return "S"
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "T"
        case .friday: return "F"
        case .saturday: return "S"
        }
    }

    var fullSymbol: String {
        switch self {
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        case .tuesday: return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday: return "Thursday"
        case .friday: return "Friday"
        case .saturday: return "Saturday"
        }
    }
}

/// A single alarm. Persisted as JSON by `PersistenceService`; contains no
/// sensitive material.
struct Alarm: Codable, Identifiable, Equatable {
    let id: UUID
    var hour: Int
    var minute: Int
    var label: String
    var isEnabled: Bool
    var repeatDays: Set<Weekday>
    var sound: AlertSound

    /// True once the user has dismissed this alarm's most recent firing, so a
    /// one-shot alarm does not resurrect itself after its time has passed.
    var consumed: Bool

    init(
        id: UUID = UUID(),
        hour: Int,
        minute: Int,
        label: String = "",
        isEnabled: Bool = true,
        repeatDays: Set<Weekday> = [],
        sound: AlertSound = .default,
        consumed: Bool = false
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.label = label
        self.isEnabled = isEnabled
        self.repeatDays = repeatDays
        self.sound = sound
        self.consumed = consumed
    }

    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var hasLabel: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isRepeating: Bool { !repeatDays.isEmpty }

    /// Human summary of the repeat configuration, e.g. "Every weekday" or
    /// "Mon, Wed, Fri". State is never communicated by color alone (§15).
    func repeatSummary(calendar: Calendar = .current) -> String {
        if repeatDays.isEmpty { return "One time" }
        let sorted = repeatDays.sorted { $0.rawValue < $1.rawValue }
        if sorted == [.monday, .tuesday, .wednesday, .thursday, .friday] { return "Every weekday" }
        if sorted.count == 7 { return "Every day" }
        let symbols = calendar.shortWeekdaySymbols
        return sorted.map { symbols[$0.rawValue - 1] }.joined(separator: ", ")
    }

    // MARK: - Next fire date

    /// Next moment this alarm should fire, or `nil` when it cannot (disabled,
    /// or a consumed/expired one-shot).
    ///
    /// DST correctness: every candidate is a wall-clock day stepped with
    /// `Calendar.date(byAdding:.day)` — which Foundation adjusts across
    /// daylight-saving boundaries — and converted through
    /// `DateComponents(date:)`, so hour/minute values are interpreted in the
    /// calendar's zone with automatic offset handling. No manual offset math
    /// anywhere (§5). A nonexistent local time (spring-forward gap) resolves
    /// to the first instant after the gap; an ambiguous time (fall-back
    /// overlap) resolves to its first occurrence.
    ///
    /// The horizon is 8 days for one-shot alarms (covers "later today" plus a
    /// skipped-gap day with margin) and 14 days for weekly patterns, so any
    /// weekday set is guaranteed to recur within the search.
    func nextFireDate(now: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        let horizonDays = repeatDays.isEmpty ? 8 : 14
        let weekdayAllowed: Set<Int>? = repeatDays.isEmpty ? nil : Set(repeatDays.map { $0.calendarIndex })

        // Start from the beginning of today so "today, later than now" is a
        // valid candidate, then walk forward day by day.
        var day = calendar.startOfDay(for: now)
        for _ in 0..<horizonDays {
            if weekdayAllowed == nil || weekdayAllowed?.contains(calendar.component(.weekday, from: day)) == true {
                var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: day)
                components.hour = hour
                components.minute = minute
                components.second = 0
                if let candidate = calendar.date(from: components), candidate > now {
                    return candidate
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return nil
    }

    /// Convenience for the common "next alarm across a list" query: earliest
    /// fire date and the alarm that owns it.
    static func nextScheduledAlarm(
        in alarms: [Alarm],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (alarm: Alarm, date: Date)? {
        var best: (alarm: Alarm, date: Date)?
        for alarm in alarms {
            guard let date = alarm.nextFireDate(now: now, calendar: calendar) else { continue }
            if best == nil || date < best!.date {
                best = (alarm, date)
            }
        }
        return best
    }
}
