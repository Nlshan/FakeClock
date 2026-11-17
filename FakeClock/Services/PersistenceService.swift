import Foundation

/// Names of the Keychain items Timer Lock uses. Only security material lives
/// in the Keychain; ordinary preferences live in `UserDefaults`.
enum SecretKey: String {
    /// The total-minutes authentication secret, stored as its decimal string.
    case authDurationMinutes = "timerlock.auth.totalMinutes"

    /// Sentinel proving first-run setup completed. Never contains the secret.
    case setupComplete = "timerlock.setup.complete"
}

/// Plain-Codable persistence for settings and small feature data.
///
/// Design decision (documented for the final report): SwiftData requires iOS
/// 17, and the deployment target is iOS 16.3, so Codable + JSON in
/// UserDefaults is the native persistence choice on this target. It keeps the
/// storage layer dependency-free and trivially testable via an injected
/// `UserDefaults` suite. Nothing sensitive is ever written here.
protocol PersistenceServicing: AnyObject {
    func save<T: Encodable>(_ value: T, forKey key: String) -> Bool
    func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T?
    func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T?
    func remove(forKey key: String)
    func containsObject(forKey key: String) -> Bool
}

final class PersistenceService: PersistenceServicing {
    static let shared = PersistenceService(defaults: .standard)

    /// Stable keys for persisted feature data.
    enum Keys {
        static let addedCities = "timerlock.worldclock.cities"
        static let alarms = "timerlock.alarms"
        static let stopwatchSession = "timerlock.stopwatch.session"
        static let timerSnapshot = "timerlock.timer.snapshot"
        static let settings = "timerlock.settings"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        encoder.sortKeys = true
        decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    func save<T: Encodable>(_ value: T, forKey key: String) -> Bool {
        do {
            let data = try encoder.encode(value)
            defaults.set(data, forKey: key)
            return true
        } catch {
            lastError = error
            return false
        }
    }

    func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            lastError = error
            // Corrupt data is discarded so the next save repairs the entry.
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }

    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }

    func containsObject(forKey key: String) -> Bool {
        defaults.object(forKey: key) != nil
    }

    /// Surfaced for tests and diagnostics; never shown to users verbatim.
    private(set) var lastError: Error?
}

extension PersistenceServicing {
    /// Convenience for non-throwing callers that ignore persistence failures.
    func saveIgnoringResult<T: Encodable>(_ value: T, forKey key: String) {
        _ = save(value, forKey: key)
    }
}
