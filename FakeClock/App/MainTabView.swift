import SwiftUI

/// The protected interface shown once unlocked (§4): four primary tabs with a
/// native bottom bar, plus Settings reached from the World Clock toolbar.
///
/// Standard `TabView` is used deliberately. It keeps each tab's view mounted
/// after first visit, so the running stopwatch, an active countdown, the alarm
/// list and added cities all survive tab switches (§4 "preserve relevant
/// state"), and it gives genuinely native transitions and safe-area handling
/// for free rather than a hand-rolled bar that could drift from platform
/// behavior.
struct MainTabView: View {
    @EnvironmentObject private var app: AppState
    @State private var selection: AppTab = .worldClock

    var body: some View {
        TabView(selection: $selection) {
            WorldClockView()
                .tabItem { Label(AppTab.worldClock.title, systemImage: AppTab.worldClock.symbol) }
                .tag(AppTab.worldClock)

            AlarmView()
                .tabItem { Label(AppTab.alarm.title, systemImage: AppTab.alarm.symbol) }
                .tag(AppTab.alarm)

            StopwatchView()
                .tabItem { Label(AppTab.stopwatch.title, systemImage: AppTab.stopwatch.symbol) }
                .tag(AppTab.stopwatch)

            TimerTabView()
                .tabItem { Label(AppTab.timer.title, systemImage: AppTab.timer.symbol) }
                .tag(AppTab.timer)

            InstagramView()
                .tabItem { Label(AppTab.instagram.title, systemImage: AppTab.instagram.symbol) }
                .tag(AppTab.instagram)
        }
        .accentColor(Theme.Palette.accent)
        // Notification taps ask for a specific tab to come forward.
        .onChange(of: app.pendingTab) { tab in
            if let tab {
                selection = tab
                app.pendingTab = nil
            }
        }
    }
}
