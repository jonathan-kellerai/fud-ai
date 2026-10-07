import Foundation
import Observation

/// The existing timer engine handles cues/notifications; this contract keeps
/// logger lifetime and deadline policy independent of UIKit and the sheet.
protocol RestTimerDriving: AnyObject {
    var cuesMuted: Bool { get set }
    var remainingSeconds: Int { get set }
    var totalSeconds: Int { get set }
    func start(seconds: Int)
    func pause()
    func resume()
    func stop()
}

@Observable
final class RestSession {
    private(set) var endDate: Date?
    private(set) var duration = 0
    private(set) var pausedSeconds: Int?
    private(set) var hasStarted = false
    var stepLabel = "Next set"
    var rangeLabel = ""
    var muted: Bool {
        didSet { driver?.cuesMuted = muted }
    }
    private let now: () -> Date
    private let driver: (any RestTimerDriving)?

    init(driver: (any RestTimerDriving)? = nil, initiallyMuted: Bool = false,
         now: @escaping () -> Date = { Date() }) {
        self.driver = driver
        self.muted = initiallyMuted
        self.now = now
        driver?.cuesMuted = initiallyMuted
    }

    var remainingSeconds: Int {
        if let pausedSeconds { return pausedSeconds }
        guard let endDate else { return 0 }
        return max(0, Int(ceil(endDate.timeIntervalSince(now()))))
    }

    var formattedTime: String { String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60) }
    var isPaused: Bool { pausedSeconds != nil }
    var isActive: Bool { hasStarted && (remainingSeconds > 0 || isPaused) }
    var progressFraction: Double { duration > 0 ? min(1, max(0, 1 - Double(remainingSeconds) / Double(duration))) : 1 }

    func start(seconds: Int) {
        hasStarted = true
        duration = max(0, seconds)
        pausedSeconds = nil
        endDate = now().addingTimeInterval(TimeInterval(duration))
        if duration > 0 { driver?.start(seconds: duration) } else { driver?.stop() }
    }

    func startIfNeeded(seconds: Int) {
        if !hasStarted { start(seconds: seconds) }
    }

    func pause() {
        guard isActive, !isPaused else { return }
        pausedSeconds = remainingSeconds
        endDate = nil
        driver?.pause()
        driver?.remainingSeconds = pausedSeconds ?? 0
    }

    func resume() {
        guard let pausedSeconds else { return }
        endDate = now().addingTimeInterval(TimeInterval(pausedSeconds))
        driver?.remainingSeconds = pausedSeconds
        self.pausedSeconds = nil
        if pausedSeconds > 0 { driver?.resume() }
    }

    func adjust(by seconds: Int) {
        let wasPaused = isPaused
        let remaining = max(0, remainingSeconds + seconds)
        let newDuration = max(remaining, duration + seconds)
        start(seconds: remaining)
        duration = newDuration
        driver?.totalSeconds = newDuration
        if wasPaused && remaining > 0 { pause() }
    }

    func stop() {
        driver?.stop()
        endDate = nil
        pausedSeconds = nil
        hasStarted = false
        duration = 0
    }
}
