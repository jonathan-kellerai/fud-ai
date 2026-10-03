import Foundation
import Testing
@testable import calorietracker

extension WorkoutLoggerLogicTests {
    @Test func restDeadlineSurvivesReopenAndKeepsMute() {
        var clock = Date(timeIntervalSince1970: 100)
        let rest = RestSession(initiallyMuted: true, now: { clock })
        rest.start(seconds: 90)
        clock = clock.addingTimeInterval(23.2)
        #expect(rest.remainingSeconds == 67)
        let end = rest.endDate
        rest.startIfNeeded(seconds: 90)
        #expect(rest.endDate == end)
        #expect(rest.muted)
        clock = clock.addingTimeInterval(100)
        #expect(rest.remainingSeconds == 0)
        #expect(!rest.isActive)
        rest.startIfNeeded(seconds: 90)
        #expect(rest.remainingSeconds == 0)
    }

    @Test func restPauseResumeAdjustAndStopUseClock() {
        var clock = Date(timeIntervalSince1970: 100)
        let rest = RestSession(now: { clock })
        rest.start(seconds: 90)
        clock = clock.addingTimeInterval(20)
        rest.pause()
        clock = clock.addingTimeInterval(100)
        #expect(rest.remainingSeconds == 70)
        rest.adjust(by: 15)
        #expect(rest.isPaused)
        #expect(rest.remainingSeconds == 85)
        rest.resume()
        clock = clock.addingTimeInterval(10)
        #expect(rest.remainingSeconds == 75)
        rest.adjust(by: -15)
        #expect(rest.remainingSeconds == 60)
        rest.stop()
        #expect(rest.remainingSeconds == 0)
        #expect(!rest.hasStarted)
        #expect(!rest.isPaused)
        rest.start(seconds: -5)
        #expect(!rest.isActive)
        rest.adjust(by: -15)
        #expect(rest.remainingSeconds == 0)
    }
}
