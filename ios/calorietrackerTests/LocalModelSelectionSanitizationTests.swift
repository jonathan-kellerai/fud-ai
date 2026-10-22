import Foundation
import Testing
@testable import calorietracker

struct LocalModelSelectionSanitizationTests {
    @Test func deletingGemmaSanitizesEveryPrimaryAndFallbackSelection() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(AIProvider.gemma4Local.rawValue, forKey: "selectedAIProvider")
        defaults.set(AIProvider.gemma4Local.rawValue, forKey: "selectedTextAIProvider")
        defaults.set(AIProvider.gemma4Local.rawValue, forKey: "selectedFallbackAIProvider")
        defaults.set(AIProvider.gemma4Local.rawValue, forKey: "selectedTextFallbackAIProvider")
        defaults.set(true, forKey: "separateTextProviderEnabled")
        defaults.set(true, forKey: "aiFallbackEnabled")
        defaults.set(true, forKey: "textAIFallbackEnabled")

        AIProviderSettings.replaceDeletedLocalGemmaSelections(defaults: defaults)

        #expect(defaults.string(forKey: "selectedAIProvider") == AIProvider.gemini.rawValue)
        #expect(defaults.string(forKey: "selectedTextAIProvider") == AIProvider.gemini.rawValue)
        #expect(defaults.string(forKey: "selectedFallbackAIProvider") == AIProvider.gemini.rawValue)
        #expect(defaults.string(forKey: "selectedTextFallbackAIProvider") == AIProvider.gemini.rawValue)
        #expect(!defaults.bool(forKey: "separateTextProviderEnabled"))
        #expect(!defaults.bool(forKey: "aiFallbackEnabled"))
        #expect(!defaults.bool(forKey: "textAIFallbackEnabled"))
    }

    @Test func deletingWhisperSanitizesPrimaryAndFallbackSelection() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(SpeechProvider.whisperBase.rawValue, forKey: "selectedSpeechProvider")
        defaults.set(SpeechProvider.whisperBase.rawValue, forKey: "selectedSpeechFallbackProvider")
        defaults.set(true, forKey: "speechFallbackEnabled")

        SpeechSettings.replaceDeletedWhisperSelections(defaults: defaults)

        #expect(defaults.string(forKey: "selectedSpeechProvider") == SpeechProvider.nativeIOS.rawValue)
        #expect(defaults.string(forKey: "selectedSpeechFallbackProvider") == SpeechProvider.groq.rawValue)
        #expect(!defaults.bool(forKey: "speechFallbackEnabled"))
    }

    @Test func retiredModelsMapToTheProviderDefault() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(AIProvider.groq.rawValue, forKey: "selectedAIProvider")
        defaults.set("qwen/qwen3.6-27b", forKey: "selectedAIModel")
        defaults.set(AIProvider.cerebras.rawValue, forKey: "selectedTextAIProvider")
        defaults.set("gemma-4-31b", forKey: "selectedTextAIModel")
        defaults.set(AIProvider.deepseek.rawValue, forKey: "selectedTextFallbackAIProvider")
        defaults.set("deepseek-v4-flash", forKey: "selectedTextFallbackAIModel")
        defaults.set("keep-me", forKey: "unrelatedUserData")

        AIProviderSettings.migrateModelRegistryIfNeeded(defaults: defaults)

        #expect(defaults.string(forKey: "selectedAIModel") == AIProvider.groq.defaultModel)
        #expect(defaults.string(forKey: "selectedTextAIModel") == AIProvider.cerebras.defaultTextModel)
        #expect(defaults.string(forKey: "selectedTextFallbackAIModel") == AIProvider.deepseek.defaultTextModel)
        #expect(defaults.string(forKey: "unrelatedUserData") == "keep-me")

        defaults.set("qwen/qwen3.6-27b", forKey: "selectedAIModel")
        AIProviderSettings.migrateModelRegistryIfNeeded(defaults: defaults)
        #expect(defaults.string(forKey: "selectedAIModel") == "qwen/qwen3.6-27b")
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "LocalModelSelectionSanitizationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (defaults, suite)
    }
}
