import Foundation

/// Shared formatting for every clock face in the app, so the stopwatch,
/// timer and world clock read as one system (spec §14).
///
/// All inputs are plain `TimeInterval` values computed from timestamps —
/// nothing here increments a counter.
enum TimeFormat {

    // MARK: Stopwatch

    /// `SS.mm` for under a minute, `M:SS.mm` under an hour, `H:MM:SS.mm`
    /// beyond — mirroring the conventional stopwatch layout. Centiseconds.
    static func stopwatch(_ interval: TimeInterval) -> String {
        let clamped = max(0, interval)
        let totalCentiseconds = Int(clamped * 100)
        let centiseconds = totalCentiseconds % 100
        let totalSeconds = totalCentiseconds / 100
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
        } else if minutes > 0 {
            return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
        } else {
            return String(format: "%d.%02d", seconds, centiseconds)
        }
    }

    /// Splits a stopwatch interval into the pieces a segmented display needs,
    /// so the view never re-implements the arithmetic.
    struct StopwatchParts {
        var hours: Int
        var minutes: Int
        var seconds: Int
        var centiseconds: Int
        var showsHours: Bool
        var showsMinutes: Bool
    }

    static func stopwatchParts(_ interval: TimeInterval) -> StopwatchParts {
        let clamped = max(0, interval)
        let totalCentiseconds = Int(clamped * 100)
        let centiseconds = totalCentiseconds % 100
        let totalSeconds = totalCentiseconds / 100
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        return StopwatchParts(
            hours: hours,
            minutes: minutes,
            seconds: seconds,
            centiseconds: centiseconds,
            showsHours: hours > 0,
            showsMinutes: hours > 0 || minutes > 0
        )
    }

    /// Signed difference between two laps, e.g. `+03.42` / `-01.07`.
    static func lapDifference(_ interval: TimeInterval) -> String {
        let sign = interval < 0 ? "-" : "+"
        let magnitude = abs(interval)
        let totalCentiseconds = Int(magnitude * 100)
        let centiseconds = totalCentiseconds % 100
        let seconds = totalCentiseconds / 100
        if seconds >= 3600 {
            return String(format: "%@%d:%02d:%02d.%02d", sign, seconds / 3600, (seconds / 60) % 60, seconds % 60, centiseconds)
        }
        if seconds >= 60 {
            return String(format: "%@%d:%02d.%02d", sign, seconds / 60, seconds % 60, centiseconds)
        }
        return String(format: "%@%d.%02d", sign, seconds, centiseconds)
    }

    // MARK: Countdown

    /// `H:MM:SS` (drops the hour when zero) for remaining countdown time.
    /// Rounds up to the next whole second so the display reads `0:01` while
    /// any time at all remains, then `0:00` only at true completion.
    static func countdown(_ interval: TimeInterval) -> String {
        let clamped = max(0, interval)
        let totalSeconds = clamped == 0 ? 0 : Int(ceil(clamped))
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// `MM:SS` from a duration under one hour, used by the notification body.
    static func shortCountdown(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(ceil(interval)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    // MARK: Clock

    /// Localized 12/24-hour time string for a date in a given calendar.
    static func clockTime(for date: Date, calendar: Calendar, use24Hour: Bool) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: Locale.current.identifier)
        formatter.setLocalizedDateFormatFromTemplate(use24Hour ? "HH:mm" : "h:mm")
        return formatter.string(from: date)
    }

    /// Seconds hand precision variant (`HH:mm:ss`) for the main world clock.
    static func clockTimeWithSeconds(for date: Date, calendar: Calendar, use24Hour: Bool) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate(use24Hour ? "HH:mm:ss" : "h:mm:ss")
        return formatter.string(from: date)
    }

    /// `Wednesday, 11 November` style date line.
    static func dateLine(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date)
    }

    /// Compact `GMT+5:30` offset label derived from the time zone itself —
    /// Foundation owns the offset, never arithmetic here (spec §5).
    static func gmtOffset(for timeZone: TimeZone, date: Date = Date()) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        if seconds == 0 { return "GMT" }
        let sign = seconds > 0 ? "+" : "−"
        let magnitude = abs(seconds)
        let hours = magnitude / 3600
        let minutes = (magnitude % 3600) / 60
        if minutes == 0 {
            return "GMT\(sign)\(hours)"
        }
        return String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }

    /// `in 2 h 15 min` / `in 45 min` style relative description for the next
    /// alarm line, avoiding a second formatting implementation in views.
    static func untilNextAlarm(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            if remainingHours == 0 { return "in \(days)d" }
            return "in \(days)d \(remainingHours)h"
        }
        if hours > 0 { return "in \(hours)h \(minutes)min" }
        if minutes > 0 { return "in \(minutes)min" }
        return "in under a minute"
    }
}
