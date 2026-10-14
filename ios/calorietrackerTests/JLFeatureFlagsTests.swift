import Foundation
import Testing
@testable import calorietracker

/// D64-1: the Challenges switch is a stored default that is on when the key is absent.
struct JLFeatureFlagsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "jl-flags-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func challengesKeyIsStable() {
        #expect(JLFeatureFlags.challengesKey == "jl.flags.challenges")
    }

    @Test func challengesAreOnWhenTheKeyIsAbsent() {
        #expect(JLFeatureFlags.challengesEnabled(in: freshDefaults()) == true)
    }

    @Test func challengesFollowAStoredFalse() {
        let defaults = freshDefaults()
        defaults.set(false, forKey: JLFeatureFlags.challengesKey)
        #expect(JLFeatureFlags.challengesEnabled(in: defaults) == false)
    }

    @Test func challengesFollowAStoredTrue() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: JLFeatureFlags.challengesKey)
        #expect(JLFeatureFlags.challengesEnabled(in: defaults) == true)
    }
}
