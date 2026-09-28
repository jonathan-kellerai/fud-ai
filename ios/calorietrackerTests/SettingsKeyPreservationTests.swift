import SwiftUI
import UIKit
import Testing
@testable import calorietracker

/// Proves the settings reorganization does not rename keys or rewrite stored values on appear.
@Suite(.serialized)
@MainActor
struct SettingsKeyPreservationTests {
    private static var retainedHosts: [Any] = []

    @Test func storageKeyConstantsStillMatchTheirLiterals() {
        #expect(HeightUnit.storageKey == "heightUnit")
        #expect(WeightUnit.storageKey == "weightUnit")
        #expect(AppThemeColor.storageKey == "appThemeColor")
        #expect(FoodMeasurementSettings.preferGramsByDefaultKey == "foodMeasurementPreferGramsByDefault")
        #expect(MealPhotoSettings.saveToGalleryKey == "saveMealPhotosToGallery")
        #expect(OptionalNutrientGoals.storageKey == "optionalNutrientGoals")
        #expect(AdaptiveGoalSettings.enabledKey == "adaptiveGoalsEnabled")
        #expect(EnergyBurnSettings.enabledKey == "energyBurnEnabledV2")
        #expect(UserProfile.storageKey == "userProfile")
        #expect(CloudBackupService.enabledKey == "cloudBackupEnabled")
        #expect(CloudBackupService.lastAtKey == "cloudBackupLastAt")
        #expect(CloudBackupService.lastHashKey == "cloudBackupLastHash")
        #expect(QuickActionSettings.storageKeys == ["quickAction.slot1", "quickAction.slot2", "quickAction.slot3"])
        #expect(AddMenuConfig.storageKey == "addMenu.config")
        #expect(OutdoorActivitySettings.enabledKey == "walkRunQuickLogEnabled")
        #expect(WorkoutTabMode.storageKey == "fudai.workouts.tab.mode.v2")
        #expect(ReconBenchStore.bridgeKey == "recon.bridgeSyncEnabled")
        #expect(ReconBenchStore.defaultsKey == "recon.bench.v1")
        #expect(HomeCardLayout.storageKey == "jl.physical.homeCards.v1")
        #expect(ActiveProgramCache.storageKey == "jl.physical.activeProgram.v1")
        #expect(NeonBridgeSettings.storageKey == "neonBridgeSettings")
        #expect(NeonBridgeKeychain.account == "neonBridgeApiKey")
        #expect(RestTimerSettings.defaultSecondsKey == "jl.restTimer.defaultSeconds")
        #expect(RestTimerSettings.clackKey == "jl.restTimer.clack")
        #expect(RestTimerSettings.bellKey == "jl.restTimer.bell")
        #expect(RestTimerSettings.hapticKey == "jl.restTimer.haptic")
        #expect(WaterSettings.enabledKey == "waterTrackingEnabled")
        #expect(WaterSettings.dailyGoalKey == "waterDailyGoalMl")
        #expect(WaterSettings.unitKey == "waterUnit")
        #expect(FastingSettings.enabledKey == "fastingTrackingEnabled")
        #expect(FastingSettings.defaultGoalMinutesKey == "fastingDefaultGoalMinutes")
    }

    @Test func openingEverySettingsScreenLeavesStoredValuesAlone() throws {
        let defaults = UserDefaults.standard
        let keys = Self.watchedKeys
        let originalDefaults = snapshot(keys, defaults: defaults)
        let originalOpenAIKey = KeychainHelper.load(key: "apikey_OpenAI")
        let originalSpeechKey = KeychainHelper.load(key: "speechApiKey_\(SpeechProvider.groq.rawValue)")
        let keychainWorks = KeychainHelper.save(key: "preserve-keychain-probe", value: "ok")
        print("PRESERVE keychainProbe works=\(keychainWorks) status=\(KeychainHelper.lastStatus)")
        defer {
            restore(originalDefaults, defaults: defaults)
            if keychainWorks {
                restoreKeychain("apikey_OpenAI", value: originalOpenAIKey)
                restoreKeychain("speechApiKey_\(SpeechProvider.groq.rawValue)", value: originalSpeechKey)
                KeychainHelper.delete(key: "preserve-keychain-probe")
            }
        }

        let stores = VisualQAStores()
        seedNonDefaultSettings(defaults: defaults)
        stores.cloudBackup.enabled = true

        let providerRoundTrip = defaults.string(forKey: "selectedAIProvider")
        let modelRoundTrip = defaults.string(forKey: "selectedAIModel")
        let textProviderRoundTrip = defaults.string(forKey: "selectedTextAIProvider")
        let speechRoundTrip = defaults.string(forKey: "selectedSpeechProvider")
        let contextRoundTrip = defaults.string(forKey: "aiUserContext")
        #expect(providerRoundTrip == AIProvider.openai.rawValue)
        #expect(modelRoundTrip == AIProvider.openai.defaultModel)
        #expect(textProviderRoundTrip == AIProvider.deepseek.rawValue)
        #expect(speechRoundTrip == SpeechProvider.groq.rawValue)
        #expect(contextRoundTrip == "preserve-context")
        if keychainWorks {
            #expect(KeychainHelper.load(key: "apikey_OpenAI") == "preserve-openai")
            #expect(KeychainHelper.load(key: "speechApiKey_\(SpeechProvider.groq.rawValue)") == "preserve-speech")
        }
        #expect(defaults.string(forKey: "aiAccessMode") == AIMode.hosted.rawValue)
        #expect(AIModeSettings.mode == .byok)

        let seeded = fingerprint(keys, defaults: defaults)
        try hostEverySettingsScreen(stores: stores)
        let after = fingerprint(keys, defaults: defaults)
        let changed = seeded.keys.filter { seeded[$0] != after[$0] }.sorted()
        for key in changed {
            print("PRESERVE changed \(key) before=\(seeded[key] ?? "") after=\(after[key] ?? "")")
        }
        #expect(changed.isEmpty)
        if keychainWorks {
            #expect(KeychainHelper.load(key: "apikey_OpenAI") == "preserve-openai")
            #expect(KeychainHelper.load(key: "speechApiKey_\(SpeechProvider.groq.rawValue)") == "preserve-speech")
        }
        #expect(defaults.string(forKey: "aiAccessMode") == AIMode.hosted.rawValue)
        #expect(AIModeSettings.mode == .byok)
    }

    @Test func bridgeTokenMigratesToTheKeychainOnce() throws {
        let defaults = UserDefaults.standard
        let originalJSON = defaults.data(forKey: NeonBridgeSettings.storageKey)
        let originalKey = NeonBridgeKeychain.load()
        defer {
            NeonBridgeKeychain.saveResultOverride = nil
            if let originalJSON {
                defaults.set(originalJSON, forKey: NeonBridgeSettings.storageKey)
            } else {
                defaults.removeObject(forKey: NeonBridgeSettings.storageKey)
            }
            if let originalKey {
                NeonBridgeKeychain.save(originalKey)
            } else {
                NeonBridgeKeychain.delete()
            }
        }

        NeonBridgeKeychain.memoryStore = [:]
        defer { NeonBridgeKeychain.memoryStore = nil }
        NeonBridgeKeychain.delete()
        let token = "preserve-bridge-token"
        let seeded = try JSONEncoder().encode(
            NeonBridgeSettings(baseURL: "https://preserve.example", apiKey: token)
        )
        defaults.set(seeded, forKey: NeonBridgeSettings.storageKey)

        let first = NeonBridgeSettings.load()
        #expect(first.apiKey == token)
        #expect(NeonBridgeKeychain.memoryStore?[NeonBridgeKeychain.account] == token)
        let stored = try #require(defaults.data(forKey: NeonBridgeSettings.storageKey))
        let decoded = try JSONDecoder().decode(NeonBridgeSettings.self, from: stored)
        #expect(decoded.apiKey == nil)
        #expect(decoded.baseURL == "https://preserve.example")

        let second = NeonBridgeSettings.load()
        #expect(second.apiKey == token)
        #expect(NeonBridgeKeychain.memoryStore?[NeonBridgeKeychain.account] == token)
        let storedAgain = try #require(defaults.data(forKey: NeonBridgeSettings.storageKey))
        let decodedAgain = try JSONDecoder().decode(NeonBridgeSettings.self, from: storedAgain)
        #expect(decodedAgain.apiKey == nil)
    }

    @Test func failedKeychainWriteKeepsTheBridgeTokenInJSON() throws {
        let defaults = UserDefaults.standard
        let originalJSON = defaults.data(forKey: NeonBridgeSettings.storageKey)
        let originalKey = NeonBridgeKeychain.load()
        defer {
            NeonBridgeKeychain.saveResultOverride = nil
            if let originalJSON {
                defaults.set(originalJSON, forKey: NeonBridgeSettings.storageKey)
            } else {
                defaults.removeObject(forKey: NeonBridgeSettings.storageKey)
            }
            if let originalKey {
                NeonBridgeKeychain.save(originalKey)
            } else {
                NeonBridgeKeychain.delete()
            }
        }

        NeonBridgeKeychain.memoryStore = [:]
        defer { NeonBridgeKeychain.memoryStore = nil }
        NeonBridgeKeychain.delete()
        NeonBridgeKeychain.saveResultOverride = false
        let token = "keep-in-json"
        let seeded = try JSONEncoder().encode(
            NeonBridgeSettings(baseURL: "https://preserve.example", apiKey: token)
        )
        defaults.set(seeded, forKey: NeonBridgeSettings.storageKey)

        let loaded = NeonBridgeSettings.load()
        #expect(loaded.apiKey == token)
        #expect(NeonBridgeKeychain.memoryStore?[NeonBridgeKeychain.account] == nil)
        let stored = try #require(defaults.data(forKey: NeonBridgeSettings.storageKey))
        let decoded = try JSONDecoder().decode(NeonBridgeSettings.self, from: stored)
        #expect(decoded.apiKey == token)
    }

    private func hostEverySettingsScreen(stores: VisualQAStores) throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let categories: [ProfileSettingsCategory?] = [nil] + ProfileSettingsCategory.allCases.map { Optional($0) }
        for category in categories {
            let root = stores.inject(ProfileView(settingsCategory: category), dynamicType: .large)
            let host = UIHostingController(rootView: root)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.beginAppearanceTransition(true, animated: false)
            host.endAppearanceTransition()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            host.beginAppearanceTransition(false, animated: false)
            host.endAppearanceTransition()
            Self.retainedHosts.append(window)
            Self.retainedHosts.append(host)
        }
    }

    private func seedNonDefaultSettings(defaults: UserDefaults) {
        defaults.set("cm", forKey: HeightUnit.storageKey)
        defaults.set("kg", forKey: WeightUnit.storageKey)
        defaults.set(AppThemeColor.graphite.rawValue, forKey: AppThemeColor.storageKey)
        defaults.set("light", forKey: "appearanceMode")
        defaults.set(false, forKey: "weekStartsOnMonday")
        defaults.set(true, forKey: FoodMeasurementSettings.preferGramsByDefaultKey)
        defaults.set(true, forKey: MealPhotoSettings.saveToGalleryKey)
        defaults.set(false, forKey: AdaptiveGoalSettings.enabledKey)
        defaults.set(true, forKey: EnergyBurnSettings.enabledKey)
        defaults.set(true, forKey: "healthKitEnabled")
        defaults.set(true, forKey: CloudBackupService.enabledKey)
        defaults.set("2020-01-01T00:00:00Z", forKey: CloudBackupService.lastAtKey)
        defaults.set("preserve-hash", forKey: CloudBackupService.lastHashKey)
        defaults.set(QuickAction.fasting.rawValue, forKey: QuickActionSettings.storageKeys[0])
        defaults.set(QuickAction.manual.rawValue, forKey: QuickActionSettings.storageKeys[1])
        defaults.set(QuickAction.favorites.rawValue, forKey: QuickActionSettings.storageKeys[2])
        defaults.set(Data("preserve-menu".utf8), forKey: AddMenuConfig.storageKey)
        defaults.set(true, forKey: OutdoorActivitySettings.enabledKey)
        defaults.set(WorkoutTabMode.library.rawValue, forKey: WorkoutTabMode.storageKey)
        defaults.set(true, forKey: ReconBenchStore.bridgeKey)
        defaults.set(Data("preserve-recon".utf8), forKey: ReconBenchStore.defaultsKey)
        defaults.set(Data("preserve-home".utf8), forKey: HomeCardLayout.storageKey)
        defaults.set(Data("preserve-program".utf8), forKey: ActiveProgramCache.storageKey)
        defaults.set(75, forKey: RestTimerSettings.defaultSecondsKey)
        defaults.set(false, forKey: RestTimerSettings.clackKey)
        defaults.set(false, forKey: RestTimerSettings.bellKey)
        defaults.set(false, forKey: RestTimerSettings.hapticKey)
        defaults.set(true, forKey: WaterSettings.enabledKey)
        defaults.set(3_500, forKey: WaterSettings.dailyGoalKey)
        defaults.set(WaterUnit.fluidOunces.rawValue, forKey: WaterSettings.unitKey)
        defaults.set(true, forKey: FastingSettings.enabledKey)
        defaults.set(18 * 60, forKey: FastingSettings.defaultGoalMinutesKey)
        defaults.set(false, forKey: "breakfastReminderEnabled")
        defaults.set(false, forKey: "weightLogReminderEnabled")
        defaults.set(true, forKey: "bodyFatLogReminderEnabled")
        defaults.set(true, forKey: "appUpdateNotificationsEnabled")
        defaults.set(AIMode.hosted.rawValue, forKey: "aiAccessMode")
        defaults.set(1, forKey: "geminiModelMigrationVersion")
        defaults.set(3, forKey: "aiModelRegistryMigrationVersion")
        defaults.set(1, forKey: "fallbackBaseURLMigrationVersion")
        defaults.set(1, forKey: "matchingSpeechProviderMigrationVersion")
        defaults.set("high", forKey: "openRouterReasoningEffort")
        defaults.set(1_234, forKey: "aiMaxResponseTokens")
        defaults.set(45, forKey: "aiRequestTimeoutSeconds")
        defaults.set(true, forKey: "separateTextProviderEnabled")
        defaults.set(true, forKey: "aiFallbackEnabled")
        defaults.set(true, forKey: "textAIFallbackEnabled")
        defaults.set(true, forKey: "speechFallbackEnabled")

        AIProviderSettings.selectedProvider = .openai
        AIProviderSettings.selectedModel = AIProvider.openai.defaultModel
        AIProviderSettings.selectedTextProvider = .deepseek
        AIProviderSettings.selectedTextModel = AIProvider.deepseek.defaultTextModel
        AIProviderSettings.selectedFallbackProvider = .openai
        AIProviderSettings.selectedFallbackModel = AIProvider.openai.defaultModel
        AIProviderSettings.selectedTextFallbackProvider = .deepseek
        AIProviderSettings.selectedTextFallbackModel = AIProvider.deepseek.defaultTextModel
        AIProviderSettings.userContext = "preserve-context"
        AIProviderSettings.setCustomBaseURL("http://primary.example/v1", for: .openai)
        AIProviderSettings.setFallbackCustomBaseURL("http://fallback.example/v1", for: .openai)
        AIProviderSettings.setAPIKey("preserve-openai", for: .openai)
        SpeechSettings.selectedProvider = .groq
        SpeechSettings.selectedFallbackProvider = .groq
        SpeechSettings.setAPIKey("preserve-speech", for: .groq)

        var goals = OptionalNutrientGoals.current
        goals.setGoal(41, for: .fiber)
        OptionalNutrientGoals.save(goals)

        if let bridge = try? JSONEncoder().encode(
            NeonBridgeSettings(baseURL: "https://preserve.example", apiKey: nil)
        ) {
            defaults.set(bridge, forKey: NeonBridgeSettings.storageKey)
        }
    }

    private static let watchedKeys = [
        HeightUnit.storageKey,
        WeightUnit.storageKey,
        AppThemeColor.storageKey,
        "appearanceMode",
        "weekStartsOnMonday",
        "hasCompletedOnboarding",
        FoodMeasurementSettings.preferGramsByDefaultKey,
        MealPhotoSettings.saveToGalleryKey,
        OptionalNutrientGoals.storageKey,
        AdaptiveGoalSettings.enabledKey,
        EnergyBurnSettings.enabledKey,
        "healthKitEnabled",
        UserProfile.storageKey,
        CloudBackupService.enabledKey,
        CloudBackupService.lastAtKey,
        CloudBackupService.lastHashKey,
        QuickActionSettings.storageKeys[0],
        QuickActionSettings.storageKeys[1],
        QuickActionSettings.storageKeys[2],
        AddMenuConfig.storageKey,
        OutdoorActivitySettings.enabledKey,
        WorkoutTabMode.storageKey,
        ReconBenchStore.bridgeKey,
        ReconBenchStore.defaultsKey,
        HomeCardLayout.storageKey,
        ActiveProgramCache.storageKey,
        NeonBridgeSettings.storageKey,
        RestTimerSettings.defaultSecondsKey,
        RestTimerSettings.clackKey,
        RestTimerSettings.bellKey,
        RestTimerSettings.hapticKey,
        WaterSettings.enabledKey,
        WaterSettings.dailyGoalKey,
        WaterSettings.unitKey,
        FastingSettings.enabledKey,
        FastingSettings.defaultGoalMinutesKey,
        "breakfastReminderEnabled",
        "weightLogReminderEnabled",
        "bodyFatLogReminderEnabled",
        "appUpdateNotificationsEnabled",
        "aiAccessMode",
        "geminiModelMigrationVersion",
        "aiModelRegistryMigrationVersion",
        "fallbackBaseURLMigrationVersion",
        "matchingSpeechProviderMigrationVersion",
        "openRouterReasoningEffort",
        "aiMaxResponseTokens",
        "aiRequestTimeoutSeconds",
        "selectedAIProvider",
        "selectedAIModel",
        "separateTextProviderEnabled",
        "selectedTextAIProvider",
        "selectedTextAIModel",
        "aiUserContext",
        "aiFallbackEnabled",
        "selectedFallbackAIProvider",
        "selectedFallbackAIModel",
        "textAIFallbackEnabled",
        "selectedTextFallbackAIProvider",
        "selectedTextFallbackAIModel",
        "customBaseURL_OpenAI",
        "fallbackCustomBaseURL_OpenAI",
        "selectedSpeechProvider",
        "speechFallbackEnabled",
        "selectedSpeechFallbackProvider",
    ]

    private struct Slot {
        var object: Any?
    }

    private func snapshot(_ keys: [String], defaults: UserDefaults) -> [String: Slot] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, Slot(object: defaults.object(forKey: $0))) })
    }

    private func restore(_ slots: [String: Slot], defaults: UserDefaults) {
        for (key, slot) in slots {
            if let object = slot.object {
                defaults.set(object, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func restoreKeychain(_ key: String, value: String?) {
        if let value {
            KeychainHelper.save(key: key, value: value)
        } else {
            KeychainHelper.delete(key: key)
        }
    }

    private func fingerprint(_ keys: [String], defaults: UserDefaults) -> [String: String] {
        Dictionary(uniqueKeysWithValues: keys.map { key in
            if let data = defaults.object(forKey: key) as? Data {
                return (key, "data:\(data.base64EncodedString())")
            }
            if let object = defaults.object(forKey: key) {
                return (key, "obj:\(String(describing: object))")
            }
            return (key, "nil")
        })
    }
}
