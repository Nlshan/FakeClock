import SwiftUI

/// Reference-typed holder for `AppSettings`.
///
/// Exists so services that need the *current* policy (LockManager's relock
/// rules, the haptics gateway) can read it live without owning a snapshot.
/// `AppState` owns the store and mirrors its value into `@Published settings`
/// for the views.
@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var value: AppSettings

    private let persistence: PersistenceServicing

    init(persistence: PersistenceServicing) {
        self.persistence = persistence
        self.value = persistence.load(AppSettings.self, forKey: PersistenceService.Keys.settings) ?? .default
        HapticsService.shared.isEnabled = value.hapticsEnabled
    }

    /// Applies a mutation, persists it, and pushes the derived effects
    /// (haptics switch) in one place so no caller can forget a step.
    func update(_ mutate: (inout AppSettings) -> Void) {
        var copy = value
        mutate(&copy)
        guard copy != value else { return }
        value = copy
        HapticsService.shared.isEnabled = copy.hapticsEnabled
        persistence.save(copy, forKey: PersistenceService.Keys.settings)
    }

    /// Live reader for non-observable consumers.
    var current: AppSettings { value }
}
