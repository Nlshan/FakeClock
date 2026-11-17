import SwiftUI

/// Central catalog of accessibility identifiers for the app's important
/// controls (§15). Views reference these constants rather than string literals
/// so UI tests and VoiceOver labels stay in sync when names change.
enum A11y {
    // Authentication
    static let lockScreen = "timerlock.screen.lock"
    static let unlockButton = "timerlock.button.unlock"
    static let biometricButton = "timerlock.button.biometric"
    static let setupScreen = "timerlock.screen.setup"
    static let setupConfirmButton = "timerlock.button.setupConfirm"

    // Tabs
    static let worldClockScreen = "timerlock.screen.worldClock"
    static let alarmScreen = "timerlock.screen.alarm"
    static let stopwatchScreen = "timerlock.screen.stopwatch"
    static let timerScreen = "timerlock.screen.timer"
    static let instagramScreen = "timerlock.screen.instagram"
    static let settingsScreen = "timerlock.screen.settings"

    // Primary actions
    static let addCityButton = "timerlock.button.addCity"
    static let addAlarmButton = "timerlock.button.addAlarm"
    static let stopwatchStart = "timerlock.button.stopwatchStart"
    static let stopwatchLap = "timerlock.button.stopwatchLap"
    static let stopwatchReset = "timerlock.button.stopwatchReset"
    static let timerStart = "timerlock.button.timerStart"
    static let timerPause = "timerlock.button.timerPause"
    static let timerCancel = "timerlock.button.timerCancel"
    static let manualLockButton = "timerlock.button.manualLock"
}
