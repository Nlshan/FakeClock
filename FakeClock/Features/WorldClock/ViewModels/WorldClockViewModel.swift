import SwiftUI

/// Owns the World Clock city list (§5).
///
/// All local-time computation goes through Foundation's `Calendar`/`TimeZone`
/// — the view model never adds or subtracts a UTC offset by hand, which is
/// what makes daylight-saving transitions correct automatically.
@MainActor
final class WorldClockViewModel: ObservableObject {
    @Published var cities: [WorldCity] {
        didSet { persist() }
    }

    /// Current instant the list is rendered against. Updated once per second
    /// by the view's timeline; a wall-clock display legitimately uses `Date`
    /// redraw (the monotonic-clock rule applies to elapsed intervals only).
    @Published private(set) var referenceDate = Date()

    /// True while the edit/reorder affordance is active.
    @Published var isEditing = false

    @Published var showingSearch = false

    private let persistence: PersistenceServicing

    init(persistence: PersistenceServicing) {
        let restored = persistence.load([WorldCity].self, forKey: PersistenceService.Keys.addedCities)
        // First run: seed with the required default, Kolkata (Asia/Kolkata).
        self.cities = restored ?? [WorldCity.kolkata]
    }

    func refresh(now: Date = Date()) {
        referenceDate = now
    }

    /// Adds a city if it is not already present and the IANA zone is valid.
    /// Returns false when duplicate or invalid so the UI can respond.
    @discardableResult
    func add(_ city: WorldCity) -> Bool {
        guard city.timeZone != nil else { return false }
        guard !cities.contains(where: { $0.timeZoneIdentifier == city.timeZoneIdentifier }) else {
            return false
        }
        cities.append(city)
        return true
    }

    func remove(at offsets: IndexSet) {
        cities.remove(atOffsets: offsets)
    }

    func remove(_ city: WorldCity) {
        cities.removeAll { $0.id == city.id }
    }

    func move(from source: IndexSet, to destination: Int) {
        cities.move(fromOffsets: source, toOffset: destination)
    }

    /// Sort by current local time, earliest first — the same idiom the Clock
    /// app offers. This does not override a manual order; it is an explicit
    /// action.
    func sortByLocalTime(now: Date = Date()) {
        cities.sort { localHour($0, now: now) < localHour($1, now: now) }
    }

    func contains(_ city: WorldCity) -> Bool {
        cities.contains { $0.timeZoneIdentifier == city.timeZoneIdentifier }
    }

    // MARK: Per-city queries

    /// A `Calendar` pinned to the city's zone. `nextDate`/components then
    /// resolve DST-aware instants for that region.
    func calendar(for city: WorldCity) -> Calendar? {
        guard let zone = city.timeZone else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = .current
        return calendar
    }

    /// Localized time string for a city at `now`.
    func timeString(for city: WorldCity, now: Date, use24Hour: Bool) -> String {
        guard let calendar = calendar(for: city) else { return "--:--" }
        return TimeFormat.clockTime(for: now, calendar: calendar, use24Hour: use24Hour)
    }

    func dateString(for city: WorldCity, now: Date) -> String {
        guard let calendar = calendar(for: city) else { return "" }
        return TimeFormat.dateLine(for: now, calendar: calendar)
    }

    func offsetLabel(for city: WorldCity, now: Date) -> String {
        guard let zone = city.timeZone else { return "" }
        return TimeFormat.gmtOffset(for: zone, date: now)
    }

    /// Day/night state from the city's *local* hour, derived via its calendar
    /// so the offset (including DST) is applied correctly. Sunrise/sunset are
    /// approximated as 06:00–18:00 local; this drives an icon only, and the
    /// numeric time is always shown, so state is never communicated by color
    /// or icon alone (§15).
    func isDay(for city: WorldCity, now: Date) -> Bool {
        guard let calendar = calendar(for: city) else { return true }
        let hour = calendar.component(.hour, from: now)
        return hour >= 6 && hour < 18
    }

    func localHour(_ city: WorldCity, now: Date) -> Int {
        guard let calendar = calendar(for: city) else { return 0 }
        return calendar.component(.hour, from: now)
    }

    /// "+1 day" / "-1 day" marker relative to the device's own day, for the
    /// city row subtitle. Computed by comparing each zone's start-of-day, so
    /// a half-zone (India :30) never miscounts.
    func dayDifference(for city: WorldCity, now: Date, home: Calendar = .current) -> Int {
        guard let calendar = calendar(for: city) else { return 0 }
        let cityMidnight = calendar.startOfDay(for: now)
        let homeMidnight = home.startOfDay(for: now)
        return calendar.dateComponents([.day], from: homeMidnight, to: cityMidnight).day ?? 0
    }

    private func persist() {
        persistence.save(cities, forKey: PersistenceService.Keys.addedCities)
    }
}
