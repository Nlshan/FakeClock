import Foundation

/// A city shown in the World Clock tab.
///
/// Only the IANA time-zone identifier is stored — never an offset — so
/// daylight-saving changes are resolved by Foundation on every render (spec §5).
struct WorldCity: Codable, Identifiable, Equatable, Hashable {
    let identifier: String
    /// IANA zone id, e.g. `Asia/Kolkata`.
    let timeZoneIdentifier: String

    var id: String { identifier }

    init(name: String, timeZoneIdentifier: String) {
        self.identifier = name
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var timeZone: TimeZone? {
        TimeZone(identifier: timeZoneIdentifier)
    }

    /// City part of the identifier: `Asia/Kolkata` → "Kolkata".
    var displayName: String {
        let parts = timeZoneIdentifier.split(separator: "/")
        guard let last = parts.last else { return identifier }
        return String(last).replacingOccurrences(of: "_", with: " ")
    }

    /// Region line above the city, e.g. "Asia", "America", "Europe".
    var regionName: String {
        let parts = timeZoneIdentifier.split(separator: "/")
        guard parts.count > 1, let first = parts.first else { return timeZoneIdentifier }
        return String(first).replacingOccurrences(of: "_", with: " ")
    }

    var accessibilityName: String {
        "\(identifier), \(regionName)"
    }

    static let kolkata = WorldCity(name: "Kolkata, India", timeZoneIdentifier: "Asia/Kolkata")
}

extension WorldCity {
    /// Searchable catalog built from the IANA zone table Foundation ships.
    ///
    /// City-level entries only (`Area/City`) and `Etc/*` pseudo-zones are
    /// excluded: region-only and GMT-offset entries would produce rows a user
    /// cannot read as a place. Names are derived from the identifier, which
    /// avoids depending on private or iOS-17-only localization helpers while
    /// staying fully offline (§2: no external services).
    static func catalog() -> [WorldCity] {
        TimeZone.knownTimeZoneIdentifiers.compactMap { identifier -> WorldCity? in
            guard !identifier.hasPrefix("Etc/"), !identifier.hasPrefix("Factory") else { return nil }
            let parts = identifier.split(separator: "/")
            guard parts.count >= 2 else { return nil }
            let city = String(parts.last!).replacingOccurrences(of: "_", with: " ")
            // Third-level entries (America/Argentina/Buenos_Aires) read better
            // with just the city half.
            let name = city
            return WorldCity(name: name, timeZoneIdentifier: identifier)
        }
        .sorted { $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending }
    }
}
