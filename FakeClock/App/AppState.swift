import SwiftUI

/// Single composition root for Timer Lock (§16: explicit state ownership,
/// dependency injection, no scattered global mutable state).
///
/// `AppState` owns the services and the shared settings, and exposes them to
/// feature view models through the SwiftUI environment. Feature views never
/// talk to the Keychain or `UNUserNotificationCenter` directly, which is also
/// what makes them unit-testable with stubs.
@MainActor
final class AppState: ObservableObject {

    // MARK: Services

    let keychain: KeychainServicing
    let persistence: PersistenceServicing
    let notificationService: NotificationService
    let authManager: AuthenticationManager
    let lockManager: LockManager
    let biometrics: BiometricService
    let clock: MonotonicClock
    let store: SettingsStore

    // MARK: Shared state

    /// Mirror of `store.value` for views. Written only through `updateSettings`
    /// so persistence, haptics and the relock policy update together.
    @Published private(set) var settings: AppSettings

    @Published private(set) var scenePhase: ScenePhase = .active

    /// Set when a notification tap should bring a tab forward; consumed by the
    /// tab controller.
    @Published var pendingTab: AppTab?

    // MARK: Init

    /// Every dependency defaults to its production implementation so
    /// `AppState()` works for the app, while tests pass stubs.
    init(
        keychain: KeychainServicing = KeychainService.shared,
        persistence: PersistenceServicing = PersistenceService(defaults: .standard),
        scheduler: NotificationScheduling? = nil,
        clock: MonotonicClock = SystemClock.shared,
        biometrics: BiometricService = BiometricService()
    ) {
        let scheduler = scheduler ?? UserNotificationScheduler()
        let store = SettingsStore(persistence: persistence)

        self.keychain = keychain
        self.persistence = persistence
        self.clock = clock
        self.store = store
        self.settings = store.value
        self.authManager = AuthenticationManager(keychain: keychain)
        self.notificationService = NotificationService(scheduler: scheduler)
        self.biometrics = biometrics
        self.lockManager = LockManager(authManager: authManager)

        // LockManager reads the live policy through the store.
        let capturedStore = store
        lockManager.settingsProvider = { capturedStore.value }

        // Decide locked vs. setup synchronously so the first rendered frame is
        // already correct — protected content can never flash (§10).
        lockManager.restoreInitialState()
    }

    // MARK: Settings mutation

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        store.update(mutate)
        settings = store.value
    }

    // MARK: Lifecycle

    func handlePhase(_ phase: ScenePhase) {
        scenePhase = phase
        lockManager.handlePhase(phase)
    }

    var isLocked: Bool { lockManager.requiresAuthentication }
    var lockState: LockManager.LockState { lockManager.state }

    func lockManually() {
        lockManager.lock()
    }

    // MARK: Feature data helpers

    func loadFeature<T: Decodable>(_ type: T.Type, key: String) -> T? {
        persistence.load(type, forKey: key)
    }

    func saveFeature<T: Encodable>(_ value: T, key: String) {
        persistence.save(value, forKey: key)
    }
}

/// Tabs of the main interface.
enum AppTab: String, CaseIterable, Hashable, Identifiable {
    case worldClock
    case alarm
    case stopwatch
    case timer
    case instagram

    var id: String { rawValue }

    var title: String {
        switch self {
        case .worldClock: return "World"
        case .alarm: return "Alarm"
        case .stopwatch: return "Stopwatch"
        case .timer: return "Timer"
        case .instagram: return "Instagram"
        }
    }

    var symbol: String {
        switch self {
        case .worldClock: return "globe.americas.fill"
        case .alarm: return "alarm.fill"
        case .stopwatch: return "stopwatch.fill"
        case .timer: return "timer"
        case .instagram: return "camera.fill"
        }
    }
}
