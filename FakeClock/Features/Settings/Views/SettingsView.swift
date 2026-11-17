import SwiftUI

/// Settings screen (§13), reached from the gear button on every tab.
///
/// Everything here is non-secret user preference. The one security action —
/// changing the secret duration — is a push to the same two-stage setup flow
/// the app used at first run, so the "choose then re-enter to verify"
/// discipline is identical and the old secret stays live until the re-entry
/// matches (§9.1).
struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @State private var showingRotation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.Metrics.spacingM) {
                    securitySection
                    appearanceSection
                    hapticsSection
                    aboutSection
                }
                .padding(.horizontal, Theme.Metrics.spacingL)
                .padding(.bottom, Theme.Metrics.spacingXXL)
            }
            .background(Theme.Palette.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationDestination(isPresented: $showingRotation) {
                SetupAuthenticationView(
                    authManager: app.authManager,
                    lockManager: app.lockManager,
                    mode: .rotation,
                    onFinish: { showingRotation = false }
                )
            }
            .accessibilityIdentifier(A11y.settingsScreen)
        }
    }

    // MARK: Sections

    private var securitySection: some View {
        SectionCard(title: "Security") {
            NavigationLink("Change Duration") {
                showingRotation = true
            }
            .accessibilityIdentifier(A11y.manualLockButton)

            Toggle("Unlock with Face ID", isOn: Binding(
                get: { app.settings.biometricEnabled },
                set: { enabled in
                    app.updateSettings { $0.biometricEnabled = enabled }
                }
            ))
            .accessibilityLabel("Unlock with Face ID")

            Picker("Relock Policy", selection: Binding(
                get: { app.settings.relockPolicy },
                set: { policy in
                    app.updateSettings { $0.relockPolicy = policy }
                }
            )) {
                ForEach(RelockPolicy.allCases) { policy in
                    Text(policy.label).tag(policy)
                }
            }
            .pickerStyle(.menu)

            Text(app.settings.relockPolicy.detail)
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)

            Button("Lock Now") {
                app.lockManually()
            }
            .foregroundStyle(Theme.Palette.danger)
            .accessibilityIdentifier(A11y.manualLockButton)
        }
    }

    private var appearanceSection: some View {
        SectionCard(title: "Appearance") {
            Picker("Theme", selection: Binding(
                get: { app.settings.appearance },
                set: { appearance in
                    app.updateSettings { $0.appearance = appearance }
                }
            )) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            }
            .pickerStyle(.segmented)

            Toggle("24-Hour Clock", isOn: Binding(
                get: { app.settings.use24HourClock },
                set: { enabled in
                    app.updateSettings { $0.use24HourClock = enabled }
                }
            ))
        }
    }

    private var hapticsSection: some View {
        SectionCard(title: "Haptics") {
            Toggle("Haptic Feedback", isOn: Binding(
                get: { app.settings.hapticsEnabled },
                set: { enabled in
                    app.updateSettings { $0.hapticsEnabled = enabled }
                }
            ))
        }
    }

    private var aboutSection: some View {
        SectionCard(title: "About") {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .font(Theme.Typography.body)

            HStack {
                Text("Build")
                Spacer()
                Text(appBuild)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .font(Theme.Typography.body)

            NavigationLink("Privacy") {
                Text("Timer Lock stores your secret duration in the device Keychain, accessible only when the device is unlocked and never migrated to iCloud or backups. Alarms, cities and stopwatch laps are plain JSON in UserDefaults and contain no personal data.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .navigationTitle("Privacy")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

/// A card-style settings section. Used instead of `Form` so the settings
/// screen reads as part of the same design system as the rest of the app.
struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.spacingM) {
            Text(title)
                .font(Theme.Typography.captionStrong)
                .foregroundStyle(Theme.Palette.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, Theme.Metrics.spacingXS)

            content
                .padding(Theme.Metrics.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
        }
    }
}