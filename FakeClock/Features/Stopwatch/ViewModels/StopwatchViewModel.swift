import SwiftUI
import Combine

/// Drives the Stopwatch screen (§7).
///
/// Keeps elapsed time accurate across backgrounding by relying on `StopwatchEngine`'s
/// monotonic timestamp math. Driven by a 1/60-second DisplayLink/Timer tick for smooth
/// rendering.
@MainActor
final class StopwatchViewModel: ObservableObject {
    @Published private(set) var engine: StopwatchEngine
    @Published private(set) var displayTime: String = "0.00"

    private let persistence: PersistenceServicing
    private var timerCancellable: AnyCancellable?

    init(
        clock: MonotonicClock = SystemClock.shared,
        persistence: PersistenceServicing = PersistenceService(defaults: .standard)
    ) {
        self.persistence = persistence
        if let savedSession = persistence.load(StopwatchSession.self, forKey: PersistenceService.Keys.stopwatchSession) {
            self.engine = StopwatchEngine(clock: clock, session: savedSession)
        } else {
            self.engine = StopwatchEngine(clock: clock)
        }
        updateDisplay()
    }

    var isRunning: Bool { engine.phase == .running }
    var isPaused: Bool { engine.phase == .paused }
    var isIdle: Bool { engine.phase == .idle }

    func start() {
        engine.start()
        startTicker()
        HapticsService.shared.light()
        persist()
    }

    func pause() {
        engine.pause()
        stopTicker()
        HapticsService.shared.medium()
        updateDisplay()
        persist()
    }

    func resume() {
        engine.resume()
        startTicker()
        HapticsService.shared.light()
        persist()
    }

    func reset() {
        engine.reset()
        stopTicker()
        HapticsService.shared.medium()
        updateDisplay()
        persist()
    }

    func addLap() {
        guard engine.addLap() else { return }
        HapticsService.shared.selectionTick()
        persist()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        if phase == .background || phase == .inactive {
            if isRunning {
                // Keep session preserved. Elapsed time is monotonic, so upon returning
                // to foreground, engine calculates true elapsed time.
                persist()
            }
        }
    }

    private func startTicker() {
        stopTicker()
        // 60 Hz ticker for smooth centisecond updates
        timerCancellable = Timer.publish(every: 0.016, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
    }

    private func stopTicker() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func updateDisplay() {
        displayTime = TimeFormat.stopwatch(engine.elapsed())
    }

    private func persist() {
        persistence.save(engine.session, forKey: PersistenceService.Keys.stopwatchSession)
    }
}
