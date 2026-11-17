import SwiftUI

/// Root of the scene graph (§10): a centralized authentication gate that
/// renders exactly one of three states — first-run setup, lock screen, or the
/// protected main application.
///
/// Anti-flash guarantee: the state is decided **synchronously** during
/// `AppState.init` (Keychain sentinel read), and this view's `body` switches
/// on `app.lockState` with no transitional placeholder. Protected content is
/// never in the hierarchy while locked, so it cannot flash at cold launch,
/// during relock, or across scene phases.
struct AppCoordinator: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch app.lockState {
            case .needsSetup:
                SetupAuthenticationView(
                    authManager: app.authManager,
                    lockManager: app.lockManager,
                    mode: .initialSetup,
                    onFinish: { app.lockManager.finishSetupAndUnlock() }
                )
            case .locked:
                AuthenticationView(
                    authManager: app.authManager,
                    lockManager: app.lockManager,
                    biometrics: app.biometrics,
                    settingsProvider: { app.store.value }
                )
                // Identity is stable while locked; switching from setup to
                // lock (or relock from unlocked) transitions without animating
                // protected content away — a plain opacity crossfade is enough
                // and never reveals the shell.
                .transition(.opacity)
            case .unlocked:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: app.lockState)
        .onChange(of: scenePhase) { phase in
            app.handlePhase(phase)
        }
        // When a verified unlock happens while backgrounded->foregrounded
        // races exist, re-evaluate on becoming active is handled by onChange
        // above; nothing else needed here.
        .preferredColorScheme(app.settings.appearance.colorSchemeOverride)
        .tint(Theme.Palette.accent)
    }
}
