import Foundation
import Security

/// Structured Keychain errors. Descriptions are safe to show to the user;
/// none of them ever contain secret material.
enum KeychainError: LocalizedError, Equatable {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedItemData
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Could not save to the Keychain (status \(status)). \(Self.advice(for: status))"
        case .loadFailed(let status):
            return "Could not read from the Keychain (status \(status)). \(Self.advice(for: status))"
        case .deleteFailed(let status):
            return "Could not delete the Keychain item (status \(status))."
        case .unexpectedItemData:
            return "The stored Keychain data is unreadable."
        case .encodingFailed:
            return "The value could not be encoded for secure storage."
        }
    }

    private static func advice(for status: OSStatus) -> String {
        switch status {
        case errSecInteractionNotAllowed:
            return "The device is locked."
        case errSecAuthFailed:
            return "Access was denied."
        default:
            return "Please try again."
        }
    }
}

/// Thin, testable abstraction over Apple's Keychain Services.
///
/// All secret material in Timer Lock goes through this service. Nothing else
/// in the codebase touches `Security` framework APIs directly.
protocol KeychainServicing: Sendable {
    func save(data: Data, for key: String) throws
    func readData(for key: String) throws -> Data?
    func readString(for key: String) throws -> String?
    func readInt(for key: String) throws -> Int?
    func delete(for key: String) throws
    func contains(key: String) throws -> Bool
}

/// Production Keychain backed by `kSecClassGenericPassword`.
///
/// Items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, so the secret is
/// unavailable while the device is locked and is never migrated to other
/// devices via iCloud Keychain or backups.
struct KeychainService: KeychainServicing {
    /// Shared instance configured with the app's bundle identifier as access
    /// group, which scopes items to this application.
    static let shared = KeychainService(service: Bundle.main.bundleIdentifier ?? "com.timerlock.app")

    let service: String

    init(service: String) {
        self.service = service
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    func save(data: Data, for key: String) throws {
        var query = baseQuery(for: key)
        // Delete any existing item first so rotation is atomic from the
        // caller's perspective; errSecItemNotFound is fine here.
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw KeychainError.deleteFailed(deleteStatus)
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    func readData(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedItemData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.loadFailed(status)
        }
    }

    func readString(for key: String) throws -> String? {
        guard let data = try readData(for: key) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedItemData
        }
        return string
    }

    func readInt(for key: String) throws -> Int? {
        guard let string = try readString(for: key) else { return nil }
        guard let value = Int(string) else {
            throw KeychainError.unexpectedItemData
        }
        return value
    }

    func delete(for key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    func contains(key: String) throws -> Bool {
        try readData(for: key) != nil
    }
}

/// In-memory Keychain stand-in used by unit tests and SwiftUI previews.
/// It mirrors the real service's error semantics without touching `Security`.
final class InMemoryKeychainService: KeychainServicing, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    /// When set, the named operation throws instead of succeeding, letting
    /// tests exercise Keychain failure paths.
    var failureInjector: ((String) -> KeychainError?)?

    func save(data: Data, for key: String) throws {
        if let error = failureInjector?("save:\(key)") { throw error }
        lock.lock(); storage[key] = data; lock.unlock()
    }

    func readData(for key: String) throws -> Data? {
        if let error = failureInjector?("read:\(key)") { throw error }
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func readString(for key: String) throws -> String? {
        guard let data = try readData(for: key) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedItemData
        }
        return string
    }

    func readInt(for key: String) throws -> Int? {
        guard let string = try readString(for: key) else { return nil }
        guard let value = Int(string) else { throw KeychainError.unexpectedItemData }
        return value
    }

    func delete(for key: String) throws {
        if let error = failureInjector?("delete:\(key)") { throw error }
        lock.lock(); storage.removeValue(forKey: key); lock.unlock()
    }

    func contains(key: String) throws -> Bool {
        try readData(for: key) != nil
    }
}
