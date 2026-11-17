import SwiftUI
import Combine

/// Drives the Timer tab (§8).
///
/// Uses `CountdownEngine` for core state. When running, it schedules a local
/// notification for the deadline so the alert fires even if the app is closed.
/// Foreground accuracy is maintained by monotonic deadline comparison.
@MainActor
final class TimerViewModel: ObservableObject {
    @Published private(set) var engine: CountdownEngine
    @Published var pickerHours: Int = 0
    @Published var pickerMinutes: Int = 0
    @Published var pickerSeconds: Int = 0

    /// Display state for the UI, refreshed by a ticker.
    @Published private(set) var remainingTime: String = "00:00:00"
    @Published private(set) var progress: Double = 0.0

    private let persistence: PersistenceServicing
    private let notificationService: NotificationService
    private var ticker: AnyCancellable?

    init(
        persistence: PersistenceServicing = PersistenceService(defaults: .standard),
        notificationService: NotificationService = NotificationService(scheduler: UserNotificationScheduler())
    ) {
        self.persistence = persistence
        self.notificationService = notificationService

        let now = Date()
        if let snapshot = persistence.load(TimerSnapshot.self, forKey: PersistenceService.Keys.timerSnapshot) {
            self.engine = CountdownEngine(snapshot: snapshot, now: now)
        } else {
            self.engine = CountdownEngine()
        }

        updateDisplay(now: now)
        if engine.phase == .running {
            startTicker()
        }
    }

    var isRunning: Bool { engine.phase == .running }
    var isPaused: Bool { engine.phase == .paused }
    var isIdle: Bool { engine.phase == .idle }
    var isFinished: Bool { engine.phase == .finished }

    func start() {
        let input = CountdownEngine.Input(hours: pickerHours, minutes: pickerMinutes, seconds: pickerSeconds)
        guard engine.start(input, now: Date()) else { return }

        Task {
            try? await notificationService.scheduleTimerCompletion(
                endDate: engine.endDate!,
                label: engine.label,
                sound: .default
            )
        }

        startTicker()
        HapticsService.shared.light()
        persist()
    }

    func pause() {
        engine.pause(now: Date())
        stopTicker()
        Task { await notificationService.cancelTimerCompletion() }
        HapticsService.shared.medium()
        persist()
    }

    func resume() {
        engine.resume(now: Date())
        if let endDate = engine.endDate {
            Task {
                try? await notificationService.scheduleTimerCompletion(
                    endDate: endDate,
                    label: engine.label,
                    sound: .default
                )
            }
        }
        startTicker()
        HapticsService.shared.light()
        persist()
    }

    func cancel() {
        engine.cancel()
        stopTicker()
        Task { await notificationService.cancelTimerCompletion() }
        HapticsService.shared.medium()
        updateDisplay(now: Date())
        persist()
    }

    func reset() {
        cancel()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        if phase == .active {
            let now = Date()
            // If the deadline passed while backgrounded, engine.tick(now:) or
            // the init(snapshot:) logic already caught it.
            updateDisplay(now: now)
            if isRunning {
                startTicker()
            }
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self else { return }
                if self.engine.tick(now: now) {
                    // Just finished!
                    self.stopTicker()
                    HapticsService.shared.success()
                    SoundService.play(.chime)
                }
                self.updateDisplay(now: now)
            }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func updateDisplay(now: Date) {
        remainingTime = TimeFormat.countdown(engine.remainingSeconds(now: now))
        progress = engine.progress(now: now)
    }

    private func persist() {
        persistence.save(engine.snapshot, forKey: PersistenceService.Keys.timerSnapshot)
    }
}
