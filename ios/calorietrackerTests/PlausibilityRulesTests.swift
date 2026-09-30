import Foundation
import Testing
@testable import calorietracker

@Suite
struct PlausibilityRulesTests {
    @Test func unitSlipAndDigitSlip() {
        let unit = PlausibilityRules.sets(name: "Bench", loadKg: 176, reps: 5, referenceLoadsKg: [80], referenceReps: [5], sessionLoadsKg: [])
        #expect(unit.contains { $0.severity == .strong && $0.message.localizedCaseInsensitiveContains("unit") })
        let digits = PlausibilityRules.sets(name: "Bench", loadKg: 800, reps: 5, referenceLoadsKg: [80], referenceReps: [5], sessionLoadsKg: [])
        #expect(digits.contains { $0.severity == .strong && $0.message.localizedCaseInsensitiveContains("10") })
    }

    @Test func epleyBoundaries() {
        let grey = PlausibilityRules.sets(name: "Squat", loadKg: 115, reps: 5, referenceLoadsKg: [100], referenceReps: [5], sessionLoadsKg: [])
        #expect(grey.contains { $0.severity == .grey })
        #expect(!grey.contains { $0.severity == .strong && $0.message.localizedCaseInsensitiveContains("heavier") })
        let edge = PlausibilityRules.sets(name: "Squat", loadKg: 135, reps: 5, referenceLoadsKg: [100], referenceReps: [5], sessionLoadsKg: [])
        #expect(edge.contains { $0.severity == .grey })
        let strong = PlausibilityRules.sets(name: "Squat", loadKg: 140, reps: 5, referenceLoadsKg: [100], referenceReps: [5], sessionLoadsKg: [])
        #expect(strong.contains { $0.severity == .strong })
    }

    @Test func absoluteLimits() {
        let flags = PlausibilityRules.sets(name: "Press", loadKg: 600, reps: 5, referenceLoadsKg: [], referenceReps: [], sessionLoadsKg: [])
        #expect(flags.contains { $0.severity == .strong })
        let reps = PlausibilityRules.sets(name: "Press", loadKg: 40, reps: 120, referenceLoadsKg: [], referenceReps: [], sessionLoadsKg: [])
        #expect(reps.contains { $0.severity == .strong })
    }

    @Test func inSessionDouble() {
        let flags = PlausibilityRules.sets(name: "Row", loadKg: 120, reps: 8, referenceLoadsKg: [], referenceReps: [], sessionLoadsKg: [50, 50])
        #expect(flags.contains { $0.severity == .grey })
    }

    @Test func weightRules() {
        let day = PlausibilityRules.weight(newKg: 84, previousKg: 80, days: 1)
        #expect(day.contains { $0.severity == .strong })
        let week = PlausibilityRules.weight(newKg: 84, previousKg: 80, days: 7)
        #expect(week.isEmpty)
        let slip = PlausibilityRules.weight(newKg: 176, previousKg: 80, days: 1)
        #expect(slip.contains { $0.severity == .strong && $0.fact.localizedCaseInsensitiveContains("kg/lb") })
    }

    @Test func bodyFatRules() {
        #expect(PlausibilityRules.bodyFat(newPercent: 24, previousPercent: 16, days: 7).contains { $0.severity == .strong })
        #expect(PlausibilityRules.bodyFat(newPercent: 20, previousPercent: 16, days: 7).contains { $0.severity == .grey })
    }

    @Test func measurementUnits() {
        let slip = PlausibilityRules.measurement(newCm: 100, previousCm: 40, days: 3)
        #expect(slip.contains { $0.severity == .strong })
        let grey = PlausibilityRules.measurement(newCm: 112, previousCm: 100, days: 10)
        #expect(grey.contains { $0.severity == .grey })
    }
}
