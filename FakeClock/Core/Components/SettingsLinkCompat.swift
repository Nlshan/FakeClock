import SwiftUI

/// iOS 16-safe wrapper around opening Settings.
///
/// `SettingsLink` is iOS 17+. On this deployment target the correct native
/// affordance is the same gear button that pushes the in-app `SettingsView`
/// onto the navigation stack, so we render a NavigationLink here. The
/// *system* settings page (notification permission) is opened from inside the
/// Settings screen via `AppSettingsOpener`.
struct SettingsLinkCompat<Label: View>: View {
    @ViewBuilder var label: () -> Label

    var body: some View {
        NavigationLink {
            SettingsView()
        } label: {
            label()
        }
        .accessibilityIdentifier(A11y.settingsScreen)
    }
}

/// Opens the app's own page in the iOS Settings app (used for the
/// notification-permission shortcut, spec §6 "handle denied permissions
/// gracefully").
enum SystemSettingsOpener {
    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}
