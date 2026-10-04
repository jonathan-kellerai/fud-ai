import SwiftUI
import UIKit
import XCTest
@testable import calorietracker

/// Renders every main screen to PNG for visual QA. Nothing here ships in the app.
///
/// CI runs this class on a Pro-size and a small simulator:
///   xcodebuild test ... -only-testing:calorietrackerTests/VisualQASnapshotTests
/// PNGs go to $VISUAL_QA_DIR (pass TEST_RUNNER_VISUAL_QA_DIR to xcodebuild) and are also
/// attached to the xcresult bundle.
///
/// Bridge calls are answered by `VisualQAStubProtocol` from local fixtures, so the real bridge is never hit.
/// Peptide fixtures reuse existing Recon Bench label/trial presets only.
@MainActor
final class VisualQASnapshotTests: XCTestCase {
    private static let sizes: [(label: String, size: DynamicTypeSize, category: UIContentSizeCategory)] = [
        ("default", .large, .large),
        ("axL", .accessibility3, .accessibilityLarge),
    ]

    // MARK: - Tabs

    func test01Home() async throws {
        try await eachSize("01-home") { _ in
            VisualQATabShell(selected: .home) {
                HomeView(quickActionRequest: nil, onQuickActionHandled: { _ in })
            }
        }
    }

    func test02TrainLiftingDay() async throws {
        let date = VisualQAFixtures.trainingDate(rest: false)
        try await eachSize("02-train-lifting-day") { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: date)
            }
        }
    }

    func test03TrainRestDay() async throws {
        let date = VisualQAFixtures.trainingDate(rest: true)
        try await eachSize("03-train-rest-day") { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: date)
            }
        }
    }

    func test04WorkoutLogging() async throws {
        let day = VisualQAFixtures.liftingDay()
        try await eachSize("04-workout-logging", sheet: {
            ProgramV2WorkoutLogView(day: day)
        }) { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false))
            }
        }
    }

    func test05RestTimer() async throws {
        let day = VisualQAFixtures.liftingDay()
        try await eachSize("05-rest-timer", sheet: {
            ProgramV2WorkoutLogView(day: day)
        }, secondSheet: {
            RestTimerSheet(defaultSeconds: 90, now: { VisualQAFixtures.referenceNow })
        }) { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false))
            }
        }
    }

    func test06DailySteps() async throws {
        VisualQAFixtures.seedSteps()
        try await eachSize("06-daily-steps") { _ in
            VisualQATabShell(selected: .train) {
                VisualQAPushed(rootTitle: "Train") {
                    StepsView(loadsHealthData: false, referenceDate: VisualQAFixtures.referenceNow)
                }
            }
        }
        // Same screen scrolled into the history list via a taller canvas.
        try await eachSize("06b-daily-steps-full", heightMultiplier: 2.2) { _ in
            VisualQATabShell(selected: .train) {
                VisualQAPushed(rootTitle: "Train") {
                    StepsView(loadsHealthData: false, referenceDate: VisualQAFixtures.referenceNow)
                }
            }
        }
    }

    func test07StepsBarEdgeCases() async throws {
        try await eachSize("07-steps-bar-edge-cases") { _ in
            VisualQAStepsEdgeCases()
        }
    }

    func test08Progress() async throws {
        try await eachSize("08-progress") { _ in
            VisualQATabShell(selected: .progress) { ProgressTabView() }
        }
    }

    func test09Coach() async throws {
        VisualQAFixtures.seedChat()
        try await eachSize("09-coach") { _ in
            VisualQATabShell(selected: .coach) { ChatView() }
        }
    }

    func test10More() async throws {
        PostUpdatePrompts.markAllSeenForFreshInstall()
        seedSettingsSubtitles()
        try await eachSize("10-more-settings", afterAppear: { window in
            VisualQAUIKit.selectTab(4, in: window)
        }) { _ in
            ContentView()
        }
    }

    // MARK: - Program, history

    func test11ProgramLibrary() async throws {
        try await eachSize("11-program-library", sheet: {
            NavigationStack { ProgramLibraryView() }
        }) { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false))
            }
        }
    }

    func test12ProgramEditor() async throws {
        let id = TrainingProgramRecord.bundledV2().id
        try await eachSize("12-program-editor", sheet: {
            NavigationStack {
                ProgramEditorView(route: .revise(id), onFinished: {})
            }
        }) { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false))
            }
        }
    }

    func test13WorkoutHistory() async throws {
        try await eachSize("13-workout-history") { _ in
            VisualQATabShell(selected: .train) {
                VisualQAPushed(rootTitle: "Train") { WorkoutHistoryListView() }
            }
        }
    }

    func test14WorkoutDetail() async throws {
        try await eachSize("14-workout-detail") { _ in
            VisualQATabShell(selected: .train) {
                VisualQAPushed(rootTitle: "Workout History") {
                    WorkoutHistoryEditView(workoutID: VisualQAFixtures.workoutID, onChanged: {})
                }
            }
        }
    }

    // MARK: - Diet

    func test15ManualFoodEntry() async throws {
        try await eachSize("15-food-manual-entry", sheet: {
            ManualEntryView(logDate: .now, onCancel: {}, onSave: { _ in })
        }) { _ in
            VisualQATabShell(selected: .home) {
                HomeView(quickActionRequest: nil, onQuickActionHandled: { _ in })
            }
        }
    }

    func test16TextFoodEntry() async throws {
        try await eachSize("16-food-text-entry", sheet: {
            TextFoodInputView(onCancel: {}, onSubmit: { _ in }, rotatesPlaceholder: false)
                .background(IronTheme.canvas)
        }) { _ in
            VisualQATabShell(selected: .home) {
                HomeView(quickActionRequest: nil, onQuickActionHandled: { _ in })
            }
        }
    }

    func test17FoodReview() async throws {
        try await eachSize("17-food-review", sheet: {
            FoodResultView(
                emoji: "🥗",
                source: .snapFood,
                name: "Chicken rice bowl",
                calories: 640,
                protein: 48,
                carbs: 72,
                fat: 16,
                servingSizeGrams: 420,
                fiber: 6,
                profile: .default,
                entriesForDate: { _ in [] },
                weightMetric: false,
                onLog: { _ in }
            )
        }) { _ in
            VisualQATabShell(selected: .home) {
                HomeView(quickActionRequest: nil, onQuickActionHandled: { _ in })
            }
        }
    }

    func test18EditFoodEntry() async throws {
        let entry = VisualQAFixtures.sampleFoodEntries().first!
        try await eachSize("18-food-edit-entry", sheet: {
            EditFoodEntryView(entry: entry)
        }) { _ in
            VisualQATabShell(selected: .home) {
                HomeView(quickActionRequest: nil, onQuickActionHandled: { _ in })
            }
        }
    }

    func test19RecentFoods() async throws {
        try await eachSize("19-food-recents", sheet: {
            RecentsView(mode: .recent, logDate: .now)
        }) { _ in
            VisualQATabShell(selected: .home) {
                HomeView(quickActionRequest: nil, onQuickActionHandled: { _ in })
            }
        }
    }

    // MARK: - Recon Bench

    func test20ReconCalculator() async throws {
        try await eachSize("20-recon-calculator") { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { ReconView(initialSection: .calculator) }
            }
        }
    }

    func test21ReconDosingDraw() async throws {
        try await eachSize("21-recon-dosing-draw") { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { ReconView(initialSection: .draw) }
            }
        }
    }

    func test22ReconCalendar() async throws {
        VisualQAFixtures.seedReconCalendar()
        try await eachSize("22-recon-calendar") { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { ReconView(initialSection: .calendar) }
            }
        }
    }

    // MARK: - AI providers

    func test23AIProvidersOnDeviceModel() async throws {
        // ProfileView's update-state initializer is fileprivate. This harness draws
        // the Gemma card in downloading, not-downloaded, and ready states.
        try await eachSize("23-ai-providers-on-device-download") { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { VisualQAOnDeviceModelSection() }
            }
        }
    }

    // MARK: - Settings

    func test24SettingsTraining() async throws {
        try await settingsScreen("24-settings-training") { ProfileView(settingsCategory: .training) }
    }

    func test25SettingsFoodAI() async throws {
        try await settingsScreen("25-settings-food-ai") { ProfileView(settingsCategory: .foodAI) }
    }

    func test26SettingsDailyTargets() async throws {
        try await settingsScreen("26-settings-daily-targets") { ProfileView(settingsCategory: .dailyTargets) }
    }

    func test27SettingsWaterFasting() async throws {
        try await settingsScreen("27-settings-water-fasting") { ProfileView(settingsCategory: .waterFasting) }
    }

    func test28SettingsShortcutsSiri() async throws {
        try await settingsScreen("28-settings-shortcuts-siri") { ShortcutsAndSiriSettingsView() }
    }

    func test29SettingsHomeMenu() async throws {
        try await settingsScreen("29-settings-home-menu") { AddMenuSettingsView() }
    }

    func test30SettingsAIProviders() async throws {
        try await settingsScreen("30-settings-ai-providers") { ProfileView(settingsCategory: .aiProviders) }
    }

    func test31SettingsOnDeviceModels() async throws {
        try await settingsScreen("31-settings-on-device-models") { ProfileView(settingsCategory: .onDeviceModels) }
    }

    func test32SettingsAdvancedAI() async throws {
        try await settingsScreen("32-settings-advanced-ai", heightMultiplier: 3) {
            ProfileView(settingsCategory: .advancedAI)
        }
    }

    func test33SettingsBodyHealth() async throws {
        try await settingsScreen("33-settings-body-health", heightMultiplier: 1.8) {
            ProfileView(settingsCategory: .bodyHealth)
        }
    }

    func test34SettingsProfile() async throws {
        try await settingsScreen("34-settings-profile") { ProfileView(settingsCategory: .profile) }
    }

    func test35SettingsDataSync() async throws {
        let backupAt = VisualQAFixtures.referenceNow.addingTimeInterval(-2 * 60 * 60)
        try await settingsScreen("35-settings-data-sync", icloudBackupAt: backupAt) {
            ProfileView(settingsCategory: .dataSync)
        }
    }

    func test36SettingsNeonBridge() async throws {
        StepsTrackingService.shared.lastSyncDate = VisualQAFixtures.referenceNow.addingTimeInterval(-600)
        try await settingsScreen("36-settings-neon-bridge") { BridgeSettingsView() }
    }

    func test37SettingsNotifications() async throws {
        try await settingsScreen("37-settings-notifications", heightMultiplier: 3) { NotificationSettingsView() }
    }

    func test38SettingsAbout() async throws {
        try await settingsScreen("38-settings-about") { AboutView() }
    }

    func test39SettingsAcknowledgements() async throws {
        try await settingsScreen("39-settings-acknowledgements") { AcknowledgementsView() }
    }

    func test40RestTimerMuted() async throws {
        let day = VisualQAFixtures.liftingDay()
        try await eachSize("40-rest-timer-muted", sheet: {
            ProgramV2WorkoutLogView(day: day)
        }, secondSheet: {
            RestTimerSheet(defaultSeconds: 90, initiallyMuted: true, now: { VisualQAFixtures.referenceNow })
        }) { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false))
            }
        }
    }

    func test41ReconCalendarSyncStatus() async throws {
        VisualQAFixtures.seedReconCalendar()
        try await settingsScreen("41-recon-calendar-sync-status", heightMultiplier: 3) {
            ReconView(initialSection: .calendar)
        }
    }

    func test42FoodReviewEstimateLooksOff() async throws {
        try await eachSize("42-food-review-estimate-looks-off", sheet: {
            FoodResultView(
                emoji: "🥗",
                source: .snapFood,
                name: "Chicken rice bowl",
                calories: 640,
                protein: 48,
                carbs: 72,
                fat: 16,
                servingSizeGrams: 420,
                fiber: 6,
                profile: .default,
                entriesForDate: { _ in [] },
                weightMetric: false,
                onLog: { _ in },
                estimateCheck: .preview(.looksOff(
                    direction: .tooLow,
                    expectedBandLabel: "1,000–1,500 kcal (a very large or restaurant-size meal)",
                    model: "jev-1.13.0"
                )),
                onReestimate: { _ in }
            )
        }) { _ in
            VisualQATabShell(selected: .home) {
                HomeView(quickActionRequest: nil, onQuickActionHandled: { _ in })
            }
        }
    }

    func test43SettingsAIProvidersEstimateCheck() async throws {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: TypeSafeSettings.enabledKey)
        defaults.set(TypeSafeEndpoint.direct.rawValue, forKey: TypeSafeSettings.endpointKey)
        defaults.set("jev-latest", forKey: TypeSafeSettings.modelKey)
        defer {
            defaults.removeObject(forKey: TypeSafeSettings.enabledKey)
            defaults.removeObject(forKey: TypeSafeSettings.endpointKey)
            defaults.removeObject(forKey: TypeSafeSettings.modelKey)
        }
        try await settingsScreen("43-settings-ai-providers-estimate-check", heightMultiplier: 4) {
            ProfileView(settingsCategory: .aiProviders)
        }
    }

    func test44SettingsAdvancedAIJevRouter() async throws {
        JevRouterSettings.visualPreview = true
        defer { JevRouterSettings.visualPreview = false }
        try await settingsScreen("44-settings-advanced-ai-jev-router", heightMultiplier: 3) {
            ProfileView(settingsCategory: .advancedAI)
        }
    }

    /// The Jev Router section alone, so the largest text size shows every wrapped toggle.
    func test44bJevRouterSection() async throws {
        JevRouterSettings.visualPreview = true
        defer { JevRouterSettings.visualPreview = false }
        try await settingsScreen("44b-jev-router-section", heightMultiplier: 3) {
            List {
                Section {
                    JevRouterAdvancedSection()
                } header: {
                    IronInfoSectionHeader(title: "Jev Router", infoTopic: .jevRouter)
                }
                .listRowBackground(AppColors.appCard)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.appBackground)
            .navigationTitle(Text("Advanced AI"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    func test45JevRouterStats() async throws {
        let defaults = UserDefaults(suiteName: "jev.router.visual")!
        defaults.removePersistentDomain(forName: "jev.router.visual")
        let telemetry = JevRouterTelemetry(defaults: defaults)
        for latency in [180, 180, 180, 320, 320, 360] {
            telemetry.recordNetwork(use: .mealMatch, latencyMs: latency, inputTokens: 500)
        }
        telemetry.recordCacheHit(use: .mealMatch)
        telemetry.recordCacheHit(use: .mealMatch)
        telemetry.recordShown(use: .mealMatch, preview: "rice", result: "accepted", latencyMs: 0, source: .cache)
        for _ in 0..<4 {
            telemetry.record(
                .mealMatch,
                .accepted(label: "chili", confidence: 0.88, llmCallsAvoided: 1),
                preview: "chili",
                latencyMs: 180,
                model: "jev-1.13.0"
            )
        }
        telemetry.record(
            .mealMatch,
            .accepted(label: "oatmeal", confidence: 0.91, llmCallsAvoided: 1),
            preview: "oatmeal",
            latencyMs: 180,
            model: "jev-1.13.0"
        )
        telemetry.record(.mealMatch, .userOverride, preview: "oatmeal", latencyMs: nil, model: nil)
        telemetry.record(
            .mealMatch,
            .fellBack(.lowConfidence),
            preview: "chili",
            latencyMs: 420,
            model: "jev-1.13.0"
        )
        defer { defaults.removePersistentDomain(forName: "jev.router.visual") }
        try await settingsScreen("45-jev-router-stats", heightMultiplier: 3) {
            JevRouterStatsView(telemetry: telemetry)
        }
    }

    func test46FoodReviewSavedMatch() async throws {
        try await eachSize("46-food-review-saved-match", sheet: {
            FoodResultView(
                emoji: "🌯",
                source: .textInput,
                name: "Chicken burrito bowl",
                calories: 640,
                protein: 42,
                carbs: 58,
                fat: 22,
                servingSizeGrams: 450,
                profile: .default,
                entriesForDate: { _ in [] },
                weightMetric: false,
                onLog: { _ in },
                savedMatch: SavedMatchBanner(entryName: "Chicken burrito bowl"),
                onEstimateInstead: {}
            )
        }) { _ in
            VisualQATabShell(selected: .home) {
                HomeView(quickActionRequest: nil, onQuickActionHandled: { _ in })
            }
        }
    }

    func test47CoachLocalAnswer() async throws {
        VisualQAFixtures.seedCoachLocalAnswer()
        try await eachSize("47-coach-local-answer") { _ in
            VisualQATabShell(selected: .coach) { ChatView() }
        }
    }

    func test48PlausibilityAlert() async throws {
        // The shared modifier every save point uses, active over a real screen.
        // The loggers keep their flag message in private @State, so the host passes it directly.
        try await eachSize("48-plausibility-alert") { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false))
            }
            .plausibilityConfirmation(
                title: "Double-check before saving",
                message: "Bench press set 2: 800 lb. Did you mean 80?",
                onSave: {},
                onEdit: {}
            )
        }
        // Body-metric copy: "Save <value> <unit>?" with a plain Save button.
        try await eachSize("48b-plausibility-weight") { _ in
            VisualQATabShell(selected: .progress) { ProgressTabView() }
                .plausibilityConfirmation(
                    title: "Save 95.0 kg?",
                    message: "This weight looks like a kg/lb unit mix-up.",
                    saveTitle: "Save",
                    onSave: {},
                    onEdit: {}
                )
        }
    }

    private func settingsScreen<Content: View>(
        _ name: String,
        heightMultiplier: CGFloat = 1,
        icloudBackupAt: Date? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) async throws {
        seedSettingsSubtitles()
        // The hub's "2 h ago" reads the live clock, so only screens that print the
        // absolute backup time pin it to the reference time.
        if let icloudBackupAt {
            VisualQAFixtures.icloudLastBackupISO = ISO8601DateFormatter().string(from: icloudBackupAt)
        }
        try await eachSize(name, heightMultiplier: heightMultiplier) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { content() }
            }
        }
    }

    private func seedSettingsSubtitles() {
        AIProviderSettings.selectedProvider = .gemini
        AIProviderSettings.selectedModel = AIProvider.gemini.defaultModel
        AIProviderSettings.setAPIKey("visual-qa-key", for: .gemini)
        VisualQAFixtures.icloudLastBackupISO = ISO8601DateFormatter().string(
            from: Date().addingTimeInterval(-2 * 60 * 60)
        )
        UserDefaults.standard.set(true, forKey: "healthKitEnabled")
        UserDefaults.standard.set("lbs", forKey: "weightUnit")
        UserDefaults.standard.set(true, forKey: "notificationsEnabled")
        let bridge = NeonBridgeSettings(baseURL: NeonBridgeSettings.defaultBaseURL, apiKey: nil)
        bridge.save()
    }


    // MARK: - Workout draft

    func test24TrainResumeWorkout() async throws {
        let day = VisualQAFixtures.liftingDay()
        let drafts = WorkoutDraftStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("visual-qa-draft-\(UUID().uuidString)", isDirectory: true)
        )
        drafts.update(day) { draft in
            if let exercise = day.exercises.first {
                draft.sets[exercise.name] = [
                    LoggedSet(weight: exercise.startLoadLb ?? 135, reps: 10, rir: 2, rpeText: "8"),
                    LoggedSet(weight: exercise.startLoadLb ?? 135, reps: 9, rir: 1, rpeText: ""),
                ]
            }
            draft.conditioningCompleted = true
        }
        VisualQAGraveyard.keep(drafts)
        try await eachSize("24-train-resume-workout") { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false))
            }
            .environment(drafts)
        }
    }

    // MARK: - Logger supersets and history

    func test49SupersetPair() async throws {
        let full = TrainingProgramBody.bundledV2().days[3].asProgramV2Day()
        let day = ProgramV2Day(
            id: full.id,
            title: full.title,
            conditioning: full.conditioning,
            conditioningMinimum: full.conditioningMinimum,
            exercises: full.exercises.filter { $0.supersetGroup != nil }
        )
        let drafts = WorkoutDraftStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("visual-qa-superset-\(UUID().uuidString)", isDirectory: true)
        )
        drafts.update(day) { draft in
            for (index, exercise) in day.exercises.enumerated() {
                let load: Double = exercise.startLoadLb ?? 25
                draft.sets[exercise.name] = [
                    LoggedSet(weight: load, reps: 14 - index, rir: 2, rpeText: ""),
                    LoggedSet(weight: load, reps: 0, rir: 2, rpeText: ""),
                ]
            }
        }
        VisualQAGraveyard.keep(drafts)
        // The draft store goes on the logger itself so it wins over the one stores.inject adds outside it.
        try await eachSize("49-superset-pair", sheet: {
            ProgramV2WorkoutLogView(day: day)
                .environment(drafts)
        }) { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false))
            }
        }
    }

    func test50LastTimeLine() async throws {
        let day = VisualQAFixtures.liftingDay()
        try await eachSize("50-last-time-line", sheet: {
            ProgramV2WorkoutLogView(day: day)
        }) { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false))
            }
        }
    }

    // MARK: - Ladders, peptides

    func test51TrainLadders() async throws {
        try await eachSize("51-train-ladders", heightMultiplier: 2) { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false), initialMode: .ladders)
            }
        }
    }

    /// All six series with graduate-at targets. HSP (a 2:00 hold) and SQT
    /// (rep progress, not ready) come first so both fit in the capture.
    func test53TrainLaddersTargets() async throws {
        VisualQAFixtures.ccLaddersJSONOverride = VisualQAFixtures.ccLaddersTargetsFirstJSON
        defer { VisualQAFixtures.ccLaddersJSONOverride = nil }
        CCLadderMemoryCache.last = nil
        defer { CCLadderMemoryCache.last = nil }
        try await eachSize("53-train-ladders-targets", heightMultiplier: 3) { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false), initialMode: .ladders)
            }
        }
    }

    /// Logger with unlogged set rows so the RPE and reps placeholders show,
    /// plus the CC leg raise finisher's graduate-at hint.
    func test54LoggerSetRowRPE() async throws {
        let full = TrainingProgramBody.bundledV2().days[1].asProgramV2Day()
        let ladder = full.exercises.filter { CCLadderLogic.isLadderExerciseName($0.name) }
        let day = ProgramV2Day(
            id: full.id,
            title: full.title,
            conditioning: full.conditioning,
            conditioningMinimum: full.conditioningMinimum,
            exercises: Array(full.exercises.prefix(1)) + ladder
        )
        let drafts = WorkoutDraftStore(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("visual-qa-set-row-\(UUID().uuidString)", isDirectory: true)
        )
        drafts.update(day) { draft in
            for exercise in day.exercises {
                let load: Double = exercise.startLoadLb ?? 0
                draft.sets[exercise.name] = [
                    LoggedSet(weight: load, reps: 10, rir: 2, rpeText: "8"),
                    LoggedSet(weight: load, reps: 0, rir: 2, rpeText: ""),
                ]
            }
        }
        VisualQAGraveyard.keep(drafts)
        CCLadderMemoryCache.last = nil
        defer { CCLadderMemoryCache.last = nil }
        try await eachSize("54-logger-set-row-rpe", sheet: {
            ProgramV2WorkoutLogView(day: day)
                .environment(drafts)
        }) { _ in
            VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: VisualQAFixtures.trainingDate(rest: false))
            }
        }
    }

    func test52HomePeptideCard() async throws {
        let savedLayout = HomeCardLayout.load()
        defer { HomeCardLayout.save(order: savedLayout.order, hidden: savedLayout.hidden) }
        HomeCardLayout.save(order: [.peptides] + HomeCardID.allCases.filter { $0 != .peptides }, hidden: [])
        try await eachSize("52-home-peptide-card") { _ in
            VisualQATabShell(selected: .home) {
                HomeView(quickActionRequest: nil, onQuickActionHandled: { _ in })
            }
        }
    }

    // MARK: - Peptides log

    func test60PeptidesToday() async throws {
        VisualQAFixtures.seedsPeptides = true
        defer { VisualQAFixtures.seedsPeptides = false }
        try await eachSize("60-peptides-today", heightMultiplier: 2.4) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { PeptidesView(initialPerson: "jonathan", referenceDate: VisualQAFixtures.peptideReferenceDate) }
            }
        }
    }

    func test61PeptideLogSheet() async throws {
        VisualQAFixtures.seedsPeptides = true
        defer { VisualQAFixtures.seedsPeptides = false }
        try await eachSize("61-peptide-log-sheet", heightMultiplier: 2, sheet: {
            PeptideLogSheet(person: "jonathan", compound: "BPC-157", now: VisualQAFixtures.peptideReferenceDate)
        }) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { PeptidesView(initialPerson: "jonathan", referenceDate: VisualQAFixtures.peptideReferenceDate) }
            }
        }
    }

    func test62PeptideLogConfirm() async throws {
        VisualQAFixtures.seedsPeptides = true
        defer { VisualQAFixtures.seedsPeptides = false }
        let draft = VisualQAFixtures.peptideReviewDraft()
        try await eachSize("62-peptide-log-confirm", heightMultiplier: 1.6, sheet: {
            PeptideLogSheet(person: "jonathan", reviewDraft: draft)
        }) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { PeptidesView(initialPerson: "jonathan", referenceDate: VisualQAFixtures.peptideReferenceDate) }
            }
        }
    }

    func test63PeptideEntryDetail() async throws {
        VisualQAFixtures.seedsPeptides = true
        defer { VisualQAFixtures.seedsPeptides = false }
        try await eachSize("63-peptide-entry-detail", heightMultiplier: 1.8) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Peptides") {
                    PeptideEntryDetailView(entryID: VisualQAFixtures.peptideVoidedRowID, clientRequestID: nil)
                }
            }
        }
    }

    func test64PeptideVials() async throws {
        VisualQAFixtures.seedsPeptides = true
        defer { VisualQAFixtures.seedsPeptides = false }
        try await eachSize("64-peptide-vials", heightMultiplier: 3) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Peptides") { PeptideVialsView(person: "jonathan") }
            }
        }
    }

    func test65PeptideVialEditor() async throws {
        VisualQAFixtures.seedsPeptides = true
        defer { VisualQAFixtures.seedsPeptides = false }
        let glow = VisualQAFixtures.peptideGlowVial()
        try await eachSize("65-peptide-vial-editor", heightMultiplier: 2.4, sheet: {
            PeptideVialEditor(vial: glow, person: "victoria")
        }) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Peptides") { PeptideVialsView(person: "victoria") }
            }
        }
    }

    func test66PeptideSchedule() async throws {
        VisualQAFixtures.seedsPeptides = true
        defer { VisualQAFixtures.seedsPeptides = false }
        try await eachSize("66-peptide-schedule", heightMultiplier: 2.4) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Peptides") { PeptideScheduleView(person: "jonathan", referenceDate: VisualQAFixtures.peptideReferenceDate) }
            }
        }
    }

    func test67PeptideHistory() async throws {
        VisualQAFixtures.seedsPeptides = true
        defer { VisualQAFixtures.seedsPeptides = false }
        try await eachSize("67-peptide-history", heightMultiplier: 3) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Peptides") { PeptideHistoryView(person: "jonathan", referenceDate: VisualQAFixtures.peptideReferenceDate) }
            }
        }
    }

    func test68PeptidesVictoria() async throws {
        VisualQAFixtures.seedsPeptides = true
        defer { VisualQAFixtures.seedsPeptides = false }
        try await eachSize("68-peptides-victoria", heightMultiplier: 2.4) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { PeptidesView(initialPerson: "victoria", referenceDate: VisualQAFixtures.peptideReferenceDate) }
            }
        }
    }

    func test69HomePeptideCardWithLogs() async throws {
        VisualQAFixtures.seedsPeptides = true
        defer { VisualQAFixtures.seedsPeptides = false }
        let savedLayout = HomeCardLayout.load()
        defer { HomeCardLayout.save(order: savedLayout.order, hidden: savedLayout.hidden) }
        HomeCardLayout.save(order: [.peptides] + HomeCardID.allCases.filter { $0 != .peptides }, hidden: [])
        try await eachSize("69-home-peptide-card-with-logs", heightMultiplier: 1.6) { _ in
            VisualQATabShell(selected: .home) {
                HomeView(quickActionRequest: nil, onQuickActionHandled: { _ in })
            }
        }
    }

    // MARK: - On-device model picker (55, 56)

    /// Apple Foundation Models picked, Gemma not downloaded, one fallback notice. Fixed state:
    /// no device availability checks and no UserDefaults reads.
    func test55SettingsOnDeviceModelPicker() async throws {
        let state = OnDeviceModelState(
            choice: .appleFoundationModels,
            apple: .available,
            gemma: .unavailable("Gemma 4 isn't downloaded and prepared yet")
        )
        let notice = OnDeviceFallbackNotice(
            provider: AIProvider.gemini.displayName,
            reason: "Could not read the workout. Please try again.",
            date: Date(timeIntervalSince1970: 1_790_000_000)
        )
        try await settingsScreen("55-settings-on-device-model-picker", heightMultiplier: 1.6) {
            OnDeviceModelPickerView(preview: state, previewNotice: notice)
        }
    }

    /// Router stats with Model tiers activity: picked on-device, image kept on cloud, and a fallback.
    func test56JevRouterStatsTiers() async throws {
        let suiteName = "jev.router.visual.tiers"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let telemetry = JevRouterTelemetry(defaults: defaults)
        for latency in [150, 190, 240] {
            telemetry.recordNetwork(use: .tierRouting, latencyMs: latency, inputTokens: 300)
        }
        telemetry.recordCacheHit(use: .tierRouting)
        telemetry.record(
            .tierRouting,
            .localShortcut(label: "Apple on-device (picked)", llmCallsAvoided: 0),
            preview: "2 eggs and toast",
            latencyMs: nil,
            model: nil
        )
        telemetry.record(
            .tierRouting,
            .localShortcut(label: "Apple on-device (picked)", llmCallsAvoided: 0),
            preview: "bench 3x10 at 60kg",
            latencyMs: nil,
            model: nil
        )
        telemetry.record(
            .tierRouting,
            .localShortcut(label: "image → cloud", llmCallsAvoided: 0),
            preview: "food_photo",
            latencyMs: nil,
            model: nil
        )
        telemetry.record(.tierRouting, .fellBack(.skipped), preview: "what should I eat tonight?", latencyMs: nil, model: nil)
        try await settingsScreen("56-jev-router-stats", heightMultiplier: 3) {
            JevRouterStatsView(telemetry: telemetry)
        }
    }

    // MARK: - Rendering

    /// The one capture entry point for harness files outside this one (the Challenges shots).
    /// It forwards to the private renderer; nothing else here is widened.
    func capture<Content: View>(
        _ name: String,
        heightMultiplier: CGFloat = 1,
        afterAppear: ((UIWindow) -> Void)? = nil,
        sheet: (() -> any View)? = nil,
        @ViewBuilder content: @escaping (DynamicTypeSize) -> Content
    ) async throws {
        try await eachSize(name, heightMultiplier: heightMultiplier, afterAppear: afterAppear, sheet: sheet, content: content)
    }

    private func eachSize<Content: View>(
        _ name: String,
        heightMultiplier: CGFloat = 1,
        afterAppear: ((UIWindow) -> Void)? = nil,
        sheet: (() -> any View)? = nil,
        secondSheet: (() -> any View)? = nil,
        @ViewBuilder content: @escaping (DynamicTypeSize) -> Content
    ) async throws {
        VisualQAFixtures.install()
        IronTheme.applyChrome()
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer {
            UIView.setAnimationsEnabled(animationsWereEnabled)
            VisualQAFixtures.uninstall()
        }
        for size in Self.sizes {
            let stores = VisualQAStores()
            let root = stores.inject(content(size.size), dynamicType: size.size)
                .transaction { $0.disablesAnimations = true }
            let sheetView = sheet.map {
                AnyView(stores.inject(AnyView($0()), dynamicType: size.size).transaction { $0.disablesAnimations = true })
            }
            let secondView = secondSheet.map {
                AnyView(stores.inject(AnyView($0()), dynamicType: size.size).transaction { $0.disablesAnimations = true })
            }
            VisualQAGraveyard.keep(stores, root, sheetView as Any, secondView as Any)
            try await render(
                name: "\(name)",
                sizeLabel: size.label,
                category: size.category,
                heightMultiplier: heightMultiplier,
                afterAppear: afterAppear,
                root: AnyView(root),
                sheet: sheetView,
                secondSheet: secondView
            )
        }
    }

    private func render(
        name: String,
        sizeLabel: String,
        category: UIContentSizeCategory,
        heightMultiplier: CGFloat,
        afterAppear: ((UIWindow) -> Void)?,
        root: AnyView,
        sheet: AnyView?,
        secondSheet: AnyView?
    ) async throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "No window scene; tests must run hosted in the app"
        )
        let screen = scene.screen.bounds
        let window = UIWindow(windowScene: scene)
        let canvasMultiplier = VisualQACanvas.cappedMultiplier(heightMultiplier)
        window.frame = CGRect(x: 0, y: 0, width: screen.width, height: (screen.height * canvasMultiplier).rounded())
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.backgroundColor = UIColor(IronTheme.canvas)

        let host = UIHostingController(rootView: root)
        host.traitOverrides.preferredContentSizeCategory = category
        host.overrideUserInterfaceStyle = .dark
        host.view.backgroundColor = UIColor(IronTheme.canvas)
        window.rootViewController = host
        VisualQAGraveyard.keep(window, host)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(700))
        if let afterAppear {
            afterAppear(window)
            try await Task.sleep(for: .milliseconds(700))
        }

        var top: UIViewController = host
        for view in [sheet, secondSheet].compactMap({ $0 }) {
            let controller = UIHostingController(rootView: view)
            controller.traitOverrides.preferredContentSizeCategory = category
            controller.overrideUserInterfaceStyle = .dark
            controller.modalPresentationStyle = .pageSheet
            VisualQAGraveyard.keep(controller)
            top.present(controller, animated: false)
            top = controller
            try await Task.sleep(for: .milliseconds(700))
        }

        // Let .task loaders hit the stub bridge and settle.
        try await Task.sleep(for: .milliseconds(1800))

        let format = UIGraphicsImageRendererFormat()
        format.scale = scene.screen.scale
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let fileName = "\(VisualQAOutput.deviceLabel)_\(sizeLabel)_\(name).png"
        if name == "10-more-settings", sizeLabel == "default", window.bounds.height <= 700 {
            VisualQADiagnostics.assertHubRowsAboveTabBar(in: window)
        }
        VisualQADiagnostics.recordNavigationBars(in: window, for: fileName)
        if let data = image.pngData() {
            VisualQAOutput.write(data, named: fileName)
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = fileName
            attachment.lifetime = .keepAlways
            add(attachment)
        } else {
            XCTFail("Could not encode \(fileName)")
        }

        // Never tear anything down while a test is running: releasing app
        // objects inside XCTest's task-local scope trips the iOS <= 26.2
        // isolated-deinit double free (swiftlang/swift#88036). Hide the
        // window and keep the whole graph alive in the graveyard instead.
        window.isHidden = true
    }
}

// MARK: - Graveyard

/// Holds every window, host, view and store the snapshot tests create for the
/// lifetime of the test process so none of them deallocate mid-test.
@MainActor
enum VisualQAGraveyard {
    private static var objects: [Any] = []

    static func keep(_ items: Any...) {
        objects.append(contentsOf: items)
    }
}

// MARK: - Diagnostics

/// Writes the navigation-bar labels present at capture time so a missing
/// large title can be told apart from a drawHierarchy capture artifact.
@MainActor
enum VisualQADiagnostics {
    private static var lines: [String] = []

    static func recordNavigationBars(in window: UIWindow, for fileName: String) {
        var found: [String] = []
        func walk(_ view: UIView, insideBar: Bool) {
            let inBar = insideBar || view is UINavigationBar
            if inBar, let label = view as? UILabel, let text = label.text, !text.isEmpty {
                let frame = label.convert(label.bounds, to: window)
                found.append(
                    "  label=\"\(text)\" alpha=\(label.alpha) hidden=\(label.isHidden) "
                    + "font=\(label.font.pointSize) frame=\(NSCoder.string(for: frame))"
                )
            }
            if let bar = view as? UINavigationBar {
                found.append(
                    "  bar prefersLarge=\(bar.prefersLargeTitles) frame=\(NSCoder.string(for: bar.convert(bar.bounds, to: window)))"
                )
            }
            for sub in view.subviews { walk(sub, insideBar: inBar) }
        }
        walk(window, insideBar: false)
        lines.append(fileName)
        lines.append(contentsOf: found.isEmpty ? ["  (no navigation bar labels)"] : found)
        let text = lines.joined(separator: "\n") + "\n"
        VisualQAOutput.write(Data(text.utf8), named: "navbar-\(VisualQAOutput.deviceLabel).txt")
    }

    static func assertHubRowsAboveTabBar(in window: UIWindow) {
        let rows = [
            ("settings.category.peptides", "Peptides"),
            ("settings.category.training", "Training"),
            ("settings.category.foodAI", "Food & AI"),
            ("settings.category.bodyHealth", "Body & Health"),
            ("settings.category.dataSync", "Data & Sync"),
            ("settings.category.notifications", "Notifications"),
            ("settings.category.about", "About"),
        ]
        let identifiers = Set(rows.map(\.0))
        scrollHubToTop(window)
        window.layoutIfNeeded()
        guard let tabBar = findTabBar(in: window) else {
            XCTFail("Missing tab bar")
            return
        }
        if let items = tabBar.items, items.count > 4 {
            XCTAssertNil(items[4].badgeValue, "More tab shows an update badge")
        }
        let tabTop = tabBar.convert(tabBar.bounds, to: window).minY
        if let scroll = tallestScrollView(in: window) {
            let coveredByTab = window.bounds.maxY - tabTop
            XCTAssertGreaterThanOrEqual(
                scroll.adjustedContentInset.bottom,
                coveredByTab,
                "More list clearance is shorter than the tab bar"
            )
        } else {
            XCTFail("Missing More hub scroll view")
        }
        let frames = hubRowFrames(in: window, identifiers: identifiers)
        for (identifier, title) in rows {
            guard let rest = frames[identifier] else {
                XCTFail("Missing More hub row \(title). \(hubLookupDebug)")
                continue
            }
            XCTAssertLessThan(rest.maxY, tabTop + 1, "\(title) sits under the tab bar at rest on iPhone SE")
        }
        scrollHubToBottom(window)
        window.layoutIfNeeded()
        writeHubScreenshot(of: window, named: "10b-more-settings-scrolled")
        let scrolled = hubRowFrames(in: window, identifiers: identifiers)
        for (identifier, title) in rows {
            guard let frame = scrolled[identifier] else {
                XCTFail("\(title) disappeared after scrolling the More hub")
                continue
            }
            XCTAssertLessThanOrEqual(frame.maxY, tabTop + 1, "\(title) can't be scrolled above the tab bar on iPhone SE")
        }
        scrollHubToTop(window)
        window.layoutIfNeeded()
    }

    private static func tallestScrollView(in view: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func walk(_ candidate: UIView) {
            if let scroll = candidate as? UIScrollView,
               scroll.contentSize.height > (best?.contentSize.height ?? 0) {
                best = scroll
            }
            for subview in candidate.subviews { walk(subview) }
        }
        walk(view)
        return best
    }

    private static func writeHubScreenshot(of window: UIWindow, named name: String) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.windowScene?.screen.scale ?? 2
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        if let data = image.pngData() {
            VisualQAOutput.write(data, named: "\(VisualQAOutput.deviceLabel)_default_\(name).png")
        }
    }

    private static var hubLookupDebug = ""

    private static func scrollHubToTop(_ view: UIView) {
        if let scroll = view as? UIScrollView {
            scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
        }
        for subview in view.subviews { scrollHubToTop(subview) }
    }

    private static func scrollHubToBottom(_ view: UIView) {
        if let scroll = view as? UIScrollView {
            let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        }
        for subview in view.subviews { scrollHubToBottom(subview) }
    }

    private static func hubRowFrames(in window: UIWindow, identifiers: Set<String>) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        var seen = Set<ObjectIdentifier>()
        var notes: [String] = []
        func keep(_ identifier: String, _ frame: CGRect) {
            guard identifiers.contains(identifier), frame.width > 40, frame.height > 20, frame.height < 220 else { return }
            if let existing = frames[identifier], existing.height >= frame.height { return }
            frames[identifier] = frame
        }
        func rowFrame(for view: UIView) -> CGRect {
            var current: UIView? = view
            while let candidate = current, candidate !== window {
                let rect = candidate.convert(candidate.bounds, to: window)
                if rect.width > 40, rect.height > 20, rect.height < 220 {
                    return rect
                }
                current = candidate.superview
            }
            return view.convert(view.bounds, to: window)
        }
        func consider(_ object: NSObject) {
            let token = ObjectIdentifier(object)
            guard seen.insert(token).inserted else { return }
            let accessibilityIdentifier = (object as? UIAccessibilityIdentification)?.accessibilityIdentifier
            let layerName = (object as? UIView)?.layer.name
            let identifier = [accessibilityIdentifier, layerName].compactMap { $0 }.first { !$0.isEmpty }
            if let identifier {
                let frame: CGRect
                if let view = object as? UIView {
                    frame = rowFrame(for: view)
                } else if let space = window.windowScene?.screen.coordinateSpace {
                    frame = window.convert(object.accessibilityFrame, from: space)
                } else {
                    frame = window.convert(object.accessibilityFrame, from: nil)
                }
                if notes.count < 12, identifier.contains("settings") {
                    notes.append("\(identifier) \(Int(frame.width))x\(Int(frame.height))")
                }
                keep(identifier, frame)
            }
            guard let view = object as? UIView else { return }
            if let elements = view.accessibilityElements {
                for case let element as NSObject in elements {
                    consider(element)
                }
            }
            let count = view.accessibilityElementCount()
            if count > 0, count < 10_000 {
                for index in 0..<count {
                    if let element = view.accessibilityElement(at: index) as? NSObject {
                        consider(element)
                    }
                }
            }
            for subview in view.subviews { consider(subview) }
        }
        consider(window)
        hubLookupDebug = notes.isEmpty ? "no settings identifiers in the window" : notes.joined(separator: "; ")
        return frames
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for subview in view.subviews {
            if let bar = findTabBar(in: subview) { return bar }
        }
        return nil
    }
}

// MARK: - Output

@MainActor
enum VisualQAOutput {
    static var directory: URL {
        let env = ProcessInfo.processInfo.environment
        if let path = env["VISUAL_QA_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("visual-qa", isDirectory: true)
    }

    static var deviceLabel: String {
        let env = ProcessInfo.processInfo.environment
        if let label = env["VISUAL_QA_DEVICE"], !label.isEmpty { return label }
        if let name = env["SIMULATOR_DEVICE_NAME"], !name.isEmpty {
            return name.filter { $0.isLetter || $0.isNumber }
        }
        let bounds = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds ?? .zero
        return "\(Int(bounds.width))x\(Int(bounds.height))"
    }

    static func write(_ data: Data, named name: String) {
        let dir = directory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent(name))
            print("VISUAL_QA wrote \(dir.appendingPathComponent(name).path)")
        } catch {
            print("VISUAL_QA write failed for \(name): \(error)")
        }
    }
}

// MARK: - Canvas

@MainActor
enum VisualQACanvas {
    /// Snapshots taller than the GPU texture limit (~8192 px) come back solid black
    /// (run 37165562250: SE 10672 px and every Pro shot over 8000 px). Caps the
    /// canvas per device; the top of each tall render stays in frame.
    static func cappedMultiplier(_ heightMultiplier: CGFloat) -> CGFloat {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let pixelHeight = (scene?.screen.bounds.height ?? 667) * (scene?.screen.scale ?? 2)
        return min(heightMultiplier, (8000 / pixelHeight * 10).rounded(.down) / 10)
    }
}

// MARK: - UIKit helpers

enum VisualQAUIKit {
    static func tabBarController(in controller: UIViewController?) -> UITabBarController? {
        guard let controller else { return nil }
        if let tab = controller as? UITabBarController { return tab }
        for child in controller.children {
            if let found = tabBarController(in: child) { return found }
        }
        return nil
    }

    static func tabBarController(in view: UIView) -> UITabBarController? {
        var responder: UIResponder? = view
        while let next = responder {
            if let tab = next as? UITabBarController { return tab }
            responder = next.next
        }
        for subview in view.subviews {
            if let found = tabBarController(in: subview) { return found }
        }
        return nil
    }

    @MainActor
    static func selectTab(_ index: Int, in window: UIWindow) {
        let tab = tabBarController(in: window.rootViewController) ?? tabBarController(in: window as UIView)
        guard let tab, let controllers = tab.viewControllers, controllers.indices.contains(index) else {
            print("VISUAL_QA could not find a tab bar controller to select tab \(index)")
            return
        }
        tab.selectedIndex = index
        tab.delegate?.tabBarController?(tab, didSelect: controllers[index])
    }
}

// MARK: - Shell views

enum VisualQATab: String, CaseIterable, Identifiable {
    case home, train, progress, coach, more
    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .train: "Train"
        case .progress: "Progress"
        case .coach: "Coach"
        case .more: "More"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .train: "figure.strengthtraining.traditional"
        case .progress: "chart.bar.fill"
        case .coach: "bubble.left.and.bubble.right.fill"
        case .more: "ellipsis"
        }
    }
}

/// Same five tabs as ContentView, with one tab pinned.
struct VisualQATabShell<Content: View>: View {
    let selected: VisualQATab
    @ViewBuilder var content: () -> Content

    var body: some View {
        TabView(selection: .constant(selected)) {
            ForEach(VisualQATab.allCases) { tab in
                Group {
                    if tab == selected {
                        content()
                    } else {
                        IronTheme.canvas
                    }
                }
                .tag(tab)
                .tabItem {
                    Image(systemName: tab.icon)
                    Text(tab.title)
                }
            }
        }
    }
}

/// Pushes `content` one level deep so the real back button shows.
struct VisualQAPushed<Content: View>: View {
    let rootTitle: String
    @ViewBuilder var content: () -> Content
    @State private var path: [String] = ["detail"]

    var body: some View {
        NavigationStack(path: $path) {
            IronTheme.canvas
                .ignoresSafeArea()
                .navigationTitle(rootTitle)
                .navigationDestination(for: String.self) { _ in
                    content()
                }
        }
    }
}

/// Bars at the values that broke or could break the label: none, zero, tiny, mid, goal, over goal.
struct VisualQAStepsEdgeCases: View {
    private let rows: [(String, Int?)] = [
        ("No data", nil),
        ("Zero", 0),
        ("Tiny", 161),
        ("Short", 1_294),
        ("Mid", 4_820),
        ("Near", 9_999),
        ("Goal", 10_000),
        ("Over", 23_456),
        ("Huge", 104_220),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Steps bar edge cases")
                    .font(.headline)
                    .foregroundStyle(IronTheme.textPrimary)
                ForEach(rows.indices, id: \.self) { index in
                    StepsHistoryRow(title: rows[index].0, steps: rows[index].1, goal: StepsView.dailyGoal)
                }
            }
            .padding()
            .ironCard()
            .padding()
        }
        .background(IronTheme.canvas)
    }
}

/// Gemma card states for visual QA. ProfileView hosts the live On-Device Models screen.
struct VisualQAOnDeviceModelSection: View {
    var body: some View {
        List {
            Section {
                Gemma4ModelSettingsView(previewState: .downloading(0.42)) {}
            } header: {
                IronSectionTitle(title: "Downloading")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                Gemma4ModelSettingsView(previewState: .notDownloaded) {}
            } header: {
                IronSectionTitle(title: "Not Downloaded")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                Gemma4ModelSettingsView(previewState: .ready) {}
            } header: {
                IronSectionTitle(title: "Ready")
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(IronTheme.canvas)
        .navigationTitle("On-Device Models")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Stores

@MainActor
final class VisualQAStores {
    let defaults: UserDefaults
    let food: FoodStore
    let weight: WeightStore
    let bodyFat: BodyFatStore
    let bodyMeasurement: BodyMeasurementStore
    let notifications: NotificationManager
    let healthKit: HealthKitManager
    let profile: ProfileStore
    let chat: ChatStore
    let water: WaterStore
    let fasting: FastingStore
    let strength: StrengthWorkoutStore
    let importedWorkouts: ImportedHealthWorkoutStore
    let weeklyChallenge: WeeklyChallengeStore
    let workoutDraft: WorkoutDraftStore
    let cloudBackup: CloudBackupService
    let peptides: PeptideLogStore

    init() {
        let suite = "visual-qa-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite) ?? .standard
        food = FoodStore(observesExternalChanges: false, defaults: defaults)
        weight = WeightStore(observesExternalChanges: false, defaults: defaults)
        water = WaterStore(defaults: defaults)
        fasting = FastingStore(defaults: defaults)
        strength = StrengthWorkoutStore(defaults: defaults)
        importedWorkouts = ImportedHealthWorkoutStore(defaults: defaults)
        weeklyChallenge = WeeklyChallengeStore(defaults: defaults)
        if let iso = VisualQAFixtures.icloudLastBackupISO {
            defaults.set(iso, forKey: CloudBackupService.lastAtKey)
            defaults.set(true, forKey: CloudBackupService.enabledKey)
        }
        workoutDraft = WorkoutDraftStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true))
        cloudBackup = CloudBackupService(defaults: defaults)
        bodyFat = BodyFatStore(observesExternalChanges: false)
        bodyMeasurement = BodyMeasurementStore()
        notifications = NotificationManager()
        healthKit = HealthKitManager()
        profile = ProfileStore()
        chat = ChatStore()
        peptides = PeptideLogStore(persistence: .inMemory, client: VisualQAPeptideClient(), autoFlush: false)
        if VisualQAFixtures.seedsPeptides {
            VisualQAFixtures.seedPeptides(peptides)
        }

        for entry in VisualQAFixtures.sampleFoodEntries() {
            _ = food.addEntry(entry)
        }
        let calendar = Calendar.current
        for offset in stride(from: 27, through: 0, by: -3) {
            let date = calendar.date(byAdding: .day, value: -offset, to: .now) ?? .now
            weight.addEntry(WeightEntry(date: date, weightKg: 93.4 - Double(27 - offset) * 0.06))
        }
        _ = water.add(milliliters: 750, on: .now)
    }

    func inject<V: View>(_ view: V, dynamicType: DynamicTypeSize) -> some View {
        view
            .environment(food)
            .environment(weight)
            .environment(bodyFat)
            .environment(bodyMeasurement)
            .environment(notifications)
            .environment(healthKit)
            .environment(profile)
            .environment(chat)
            .environment(water)
            .environment(fasting)
            .environment(strength)
            .environment(importedWorkouts)
            .environment(weeklyChallenge)
            .environment(workoutDraft)
            .environment(cloudBackup)
            .environment(peptides)
            .environment(\.dynamicTypeSize, dynamicType)
            .tint(IronTheme.bloodText)
            .preferredColorScheme(.dark)
            .overlay { IronGrainOverlay().allowsHitTesting(false) }
    }
}

// MARK: - Fixtures

@MainActor
enum VisualQAFixtures {
    nonisolated static let host = VisualQAStubStorage.host
    static let workoutID = "qa-workout-1"
    static var icloudLastBackupISO: String?

    /// Fixed clock for the shots that print or count from "now": Wed 2026-10-07 09:00 New York.
    /// Program V2 week 2, clear of the 10/19-10/25 reduction week.
    static let referenceNow: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9)) ?? .now
    }()
    private static var savedSettings: NeonBridgeSettings?

    static func install() {
        VisualQAStubStorage.setResponses(buildResponses())
        URLProtocol.registerClass(VisualQAStubProtocol.self)
        if savedSettings == nil {
            savedSettings = NeonBridgeService.shared.settings
        }
        // Fake key, never persisted: the stub rejects peptide calls without it.
        NeonBridgeService.shared.settings = NeonBridgeSettings(baseURL: "https://\(host)", apiKey: VisualQAStubStorage.bridgeKey)
    }

    static func uninstall() {
        URLProtocol.unregisterClass(VisualQAStubProtocol.self)
        if let savedSettings {
            NeonBridgeService.shared.settings = savedSettings
        }
    }

    static func trainingDate(rest: Bool) -> Date {
        let body = TrainingProgramBody.bundledV2()
        let calendar = Calendar.current
        var date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: referenceNow) ?? referenceNow
        for _ in 0..<90 {
            switch TrainingProgramSchedule.resolve(body, on: date) {
            case .session:
                if !rest { return date }
            case .rest:
                if rest { return date }
            case .upcoming:
                break
            }
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return referenceNow
    }

    static func liftingDay() -> ProgramV2Day {
        TrainingProgramBody.bundledV2().days[0].asProgramV2Day()
    }

    static func isoDay(offset: Int, from base: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: base) ?? base
        return formatter.string(from: date)
    }

    static func seedSteps() {
        let values: [Int?] = [161, 4_820, 7_842, 8_773, 12_973, 1_294, 0]
        let service = StepsTrackingService.shared
        service.todaySteps = values[0] ?? 0
        service.last7Days = values.enumerated().map { index, steps in
            StepsDay(
                date: isoDay(offset: index, from: referenceNow),
                steps: steps,
                met: steps.map { $0 >= StepsView.dailyGoal },
                logged: steps != nil,
                source: "healthkit",
                device: "iPhone",
                origin: nil
            )
        }
        service.lastSyncDate = referenceNow.addingTimeInterval(-600)
        service.lastSyncError = nil
    }

    static func seedCoachLocalAnswer() {
        let chat = ChatStore()
        VisualQAGraveyard.keep(chat)
        chat.reset()
        chat.append(ChatMessage(role: .user, content: "how many steps have I done today?"))
        chat.append(ChatMessage(
            role: .assistant,
            content: "You're at 6,420 steps today, 64% of your 10,000 goal.",
            routerAction: .localAnswer
        ))
    }

    static func seedChat() {
        let chat = ChatStore()
        VisualQAGraveyard.keep(chat)
        chat.reset()
        chat.append(ChatMessage(role: .user, content: "How did my training week look?"))
        chat.append(ChatMessage(role: .assistant, content: "You hit four of five sessions. Lower A moved up 5 lb on the squat, and steps averaged 6,100 a day. Tomorrow is Upper Push; aim for 8,000 steps."))
        chat.append(ChatMessage(role: .user, content: "What should I eat after lifting?"))
    }

    static func seedReconCalendar() {
        let store = ReconBenchStore()
        VisualQAGraveyard.keep(store)
        for entry in store.entries {
            store.delete(id: entry.id)
        }
        let start = ReconMath.todayISO()
        // Existing presets only: Tesamorelin 1.4 mg/day (LABEL), Retatrutide 2 mg/week (TRIAL).
        store.add(ReconMath.ScheduleEntry(
            id: "qa-tesa", person: "jonathan", compound: "tesamorelin",
            dose: 1.4, doseUnit: "mg", draw: nil,
            freq: ReconMath.Frequency(type: "daily"), start: start, weeks: 4
        ))
        store.add(ReconMath.ScheduleEntry(
            id: "qa-reta", person: "jonathan", compound: "retatrutide",
            dose: 2, doseUnit: "mg", draw: nil,
            freq: ReconMath.Frequency(type: "weekly"), start: start, weeks: 8
        ))
    }

    static func sampleFoodEntries() -> [FoodEntry] {
        let calendar = Calendar.current
        func at(_ hour: Int) -> Date {
            calendar.date(bySettingHour: hour, minute: 15, second: 0, of: .now) ?? .now
        }
        return [
            FoodEntry(name: "Greek yogurt with berries", calories: 280, protein: 24, carbs: 32, fat: 6, timestamp: at(7), emoji: "🫐", source: .manual, mealType: .breakfast),
            FoodEntry(name: "Egg white omelette", calories: 210, protein: 30, carbs: 4, fat: 8, timestamp: at(7), emoji: "🍳", source: .textInput, mealType: .breakfast),
            FoodEntry(name: "Chicken rice bowl", calories: 640, protein: 48, carbs: 72, fat: 16, timestamp: at(12), emoji: "🥗", source: .snapFood, mealType: .lunch),
            FoodEntry(name: "Protein shake", calories: 160, protein: 30, carbs: 5, fat: 2, timestamp: at(15), emoji: "🥤", source: .barcode, mealType: .snack),
        ]
    }

    static func sampleWorkouts() -> [RemoteWorkout] {
        let days = TrainingProgramBody.bundledV2().days
        return days.prefix(4).enumerated().map { index, day in
            RemoteWorkout(
                id: index == 0 ? workoutID : "qa-workout-\(index + 1)",
                kind: "strength",
                programVersion: "program-v2",
                programDay: day.name,
                title: day.name,
                units: "lb",
                sessionDate: isoDay(offset: index + 1),
                conditioning: index % 2 == 0 ? "Bike 20 min zone 2" : nil,
                notes: [],
                contentHash: nil,
                synthetic: nil,
                recordedAt: nil
            )
        }
    }

    static func sampleWorkoutDetail() -> WorkoutDetailResponse {
        let workout = sampleWorkouts()[0]
        let day = TrainingProgramBody.bundledV2().days[0]
        var sets: [RemoteWorkoutSet] = []
        var order = 1
        for (exerciseIndex, exercise) in day.exercises.prefix(3).enumerated() {
            for setIndex in 0..<3 {
                sets.append(RemoteWorkoutSet(
                    id: "qa-set-\(order)",
                    workoutId: workout.id,
                    setOrder: order,
                    exercise: exercise.name,
                    loadLb: Double(185 - exerciseIndex * 40 + setIndex * 5),
                    reps: 8 - setIndex,
                    rir: 2,
                    rpe: nil
                ))
                order += 1
            }
        }
        return WorkoutDetailResponse(workout: workout, sets: sets)
    }

    static let upperPhysiqueWorkoutID = "qa-workout-4"

    /// Day 4 session with the curl + pressdown superset, for the logger's Last line.
    static func upperPhysiqueWorkoutDetail() -> WorkoutDetailResponse {
        let workout = sampleWorkouts()[3]
        let rows: [(String, Double, Int, Int?)] = [
            ("Cable or DB curl", 25, 15, 4),
            ("Triceps pressdown", 125, 14, 2),
            ("Cable or DB curl", 25, 14, 3),
            ("Triceps pressdown", 125, 12, 1),
        ]
        let sets = rows.enumerated().map { index, row in
            RemoteWorkoutSet(
                id: "qa-set-4-\(index + 1)",
                workoutId: workout.id,
                setOrder: index + 1,
                exercise: row.0,
                loadLb: row.1,
                reps: row.2,
                rir: row.3,
                rpe: nil
            )
        }
        return WorkoutDetailResponse(workout: workout, sets: sets)
    }

    static func peptideTodayJSON() -> String {
        let today = isoDay(offset: 0)
        return """
        {"date":"\(today)","timezone":"America/New_York","has_active_schedules":true,
         "planned":[{"id":"qa-planned-1","datetime":"\(today)T12:00:00Z","compound":"Tesamorelin","dose":1.4,"units":"mg",
                     "status":"planned","schedule_id":"qa-schedule-1","source_vial":"qa-vial-1","voided":false,
                     "dose_deviates_from_planned":false,"badges":["LABEL"]}],
         "completed":[{"id":"qa-done-1","datetime":"\(today)T11:30:00Z","compound":"BPC-157","dose":500,"units":"mcg",
                       "status":"completed","voided":false,"dose_deviates_from_planned":false,"badges":[]}]}
        """
    }

    static let peptideInventoryJSON = """
    {"inventory":[{"id":"qa-vial-1","compound":"Tesamorelin","calc_gate":null,"concentration_basis":null,
                   "identity_basis":null,"badges":[],"warnings":[]}]}
    """

    static let peptideSchedulesJSON = """
    {"schedules":[{"id":"qa-schedule-1","active":true}]}
    """

    /// When set, /api/cc/ladders answers with this payload instead of `ccLaddersJSON`.
    static var ccLaddersJSONOverride: String?

    /// Modeled on the /api/cc/ladders response with book graduate-at targets
    /// for all six series. HSP steps 1-3 are timed holds; SQT and HSP show
    /// within-step rep progress (improved, not ready); LGR is ready.
    static let ccLaddersTargetsFirstJSON = #"""
    {"generated_at":"2026-09-30T12:29:09.967Z",
     "rule":{"description":"A session qualifies when it reaches the step graduate-at target. Ready after 2 consecutive qualifying sessions.","required_streak":2,"master_step":10,"targets_by_series":{"PSH":{"1":{"sets":3,"reps":50,"hold_sec":null,"label":"3×50"},"2":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":2,"reps":25,"hold_sec":null,"label":"2×25"},"5":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"6":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"7":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"8":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"9":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"10":{"sets":1,"reps":100,"hold_sec":null,"label":"1×100"}},"SQT":{"1":{"sets":3,"reps":50,"hold_sec":null,"label":"3×50"},"2":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":2,"reps":50,"hold_sec":null,"label":"2×50"},"5":{"sets":2,"reps":30,"hold_sec":null,"label":"2×30"},"6":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"7":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"8":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"9":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"10":{"sets":2,"reps":50,"hold_sec":null,"label":"2×50"}},"PLL":{"1":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"2":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"3":{"sets":3,"reps":20,"hold_sec":null,"label":"3×20"},"4":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"5":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"6":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"7":{"sets":2,"reps":9,"hold_sec":null,"label":"2×9"},"8":{"sets":2,"reps":8,"hold_sec":null,"label":"2×8"},"9":{"sets":2,"reps":7,"hold_sec":null,"label":"2×7"},"10":{"sets":2,"reps":6,"hold_sec":null,"label":"2×6"}},"LGR":{"1":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"2":{"sets":3,"reps":35,"hold_sec":null,"label":"3×35"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":3,"reps":15,"hold_sec":null,"label":"3×15"},"5":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"6":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"7":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"8":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"9":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"10":{"sets":2,"reps":30,"hold_sec":null,"label":"2×30"}},"BRG":{"1":{"sets":3,"reps":50,"hold_sec":null,"label":"3×50"},"2":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":2,"reps":25,"hold_sec":null,"label":"2×25"},"5":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"6":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"7":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"8":{"sets":2,"reps":8,"hold_sec":null,"label":"2×8"},"9":{"sets":2,"reps":6,"hold_sec":null,"label":"2×6"},"10":{"sets":2,"reps":30,"hold_sec":null,"label":"2×30"}},"HSP":{"1":{"sets":1,"reps":null,"hold_sec":120,"label":"2:00 hold"},"2":{"sets":1,"reps":null,"hold_sec":60,"label":"1:00 hold"},"3":{"sets":1,"reps":null,"hold_sec":120,"label":"2:00 hold"},"4":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"5":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"6":{"sets":2,"reps":12,"hold_sec":null,"label":"2×12"},"7":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"8":{"sets":2,"reps":8,"hold_sec":null,"label":"2×8"},"9":{"sets":2,"reps":6,"hold_sec":null,"label":"2×6"},"10":{"sets":2,"reps":5,"hold_sec":null,"label":"2×5"}}}},
     "active_program":{"id":"qa-program","name":"Program V2","version":3},
     "series":[
      {"series":"HSP","label":"Handstand push-up","current_step":1,"step_name":"Wall headstand","since":"2026-09-15T04:00:00.000Z","target_reps":null,"target_sets":1,"target_hold_sec":120,"target_label":"2:00 hold","progress":{"best_total_reps_last":75,"best_total_reps_prev":60,"delta":15,"improved":true,"pct_of_target":62.5},"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[{"workout_id":"qa-hsp-2","session_date":"2026-09-28","program_day":null,"title":null,"exercise":"Wall headstand","step":1,"sets":[{"set_order":1,"reps":75,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["rep_progress","hold_below_target"],"total_reps":75,"pct_of_target":62.5},{"workout_id":"qa-hsp-1","session_date":"2026-09-25","program_day":null,"title":null,"exercise":"Wall headstand","step":1,"sets":[{"set_order":1,"reps":60,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["hold_below_target"],"total_reps":60,"pct_of_target":50}],"steps":[
        {"step":1,"name":"Wall headstand","target_sets":1,"target_reps":null,"target_hold_sec":120,"target_label":"2:00 hold"},
        {"step":2,"name":"Crow stand","target_sets":1,"target_reps":null,"target_hold_sec":60,"target_label":"1:00 hold"},
        {"step":3,"name":"Wall handstand","target_sets":1,"target_reps":null,"target_hold_sec":120,"target_label":"2:00 hold"},
        {"step":4,"name":"Half handstand push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":5,"name":"Handstand push-up","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":6,"name":"Close handstand push-up","target_sets":2,"target_reps":12,"target_hold_sec":null,"target_label":"2×12"},
        {"step":7,"name":"Uneven handstand push-up","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":8,"name":"Half one-arm handstand push-up","target_sets":2,"target_reps":8,"target_hold_sec":null,"target_label":"2×8"},
        {"step":9,"name":"Lever handstand push-up","target_sets":2,"target_reps":6,"target_hold_sec":null,"target_label":"2×6"},
        {"step":10,"name":"One-arm handstand push-up","target_sets":2,"target_reps":5,"target_hold_sec":null,"target_label":"2×5"}]},
      {"series":"SQT","label":"Squat","current_step":2,"step_name":"Jackknife squat","since":"2026-09-15T04:00:00.000Z","target_reps":40,"target_sets":3,"target_hold_sec":null,"target_label":"3×40","progress":{"best_total_reps_last":52,"best_total_reps_prev":46,"delta":6,"improved":true,"pct_of_target":43.3},"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":true,"program_exercises":[{"day":"Lower B + Cond","exercise":"CC squat ladder - step 2 Jackknife squat","step":2,"sets":2,"reps":"8-15"}],"last_event":null,"sessions":[{"workout_id":"qa-sqt-2","session_date":"2026-09-29","program_day":null,"title":null,"exercise":"Jackknife squat","step":2,"sets":[{"set_order":1,"reps":18,"rir":null,"load_lb":0},{"set_order":2,"reps":17,"rir":null,"load_lb":0},{"set_order":3,"reps":17,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["rep_progress","reps_below_target"],"total_reps":52,"pct_of_target":43.3},{"workout_id":"qa-sqt-1","session_date":"2026-09-26","program_day":null,"title":null,"exercise":"Jackknife squat","step":2,"sets":[{"set_order":1,"reps":16,"rir":null,"load_lb":0},{"set_order":2,"reps":15,"rir":null,"load_lb":0},{"set_order":3,"reps":15,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["reps_below_target"],"total_reps":46,"pct_of_target":38.3}],"steps":[
        {"step":1,"name":"Shoulderstand squat","target_sets":3,"target_reps":50,"target_hold_sec":null,"target_label":"3×50"},
        {"step":2,"name":"Jackknife squat","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":3,"name":"Supported squat","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Half squat","target_sets":2,"target_reps":50,"target_hold_sec":null,"target_label":"2×50"},
        {"step":5,"name":"Full squat","target_sets":2,"target_reps":30,"target_hold_sec":null,"target_label":"2×30"},
        {"step":6,"name":"Close squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":7,"name":"Uneven squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":8,"name":"Half one-leg squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":9,"name":"Assisted one-leg squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":10,"name":"One-leg squat (pistol)","target_sets":2,"target_reps":50,"target_hold_sec":null,"target_label":"2×50"}]},
      {"series":"LGR","label":"Leg raise","current_step":1,"step_name":"Knee tuck","since":"2026-09-15T04:00:00.000Z","target_reps":40,"target_sets":3,"target_hold_sec":null,"target_label":"3×40","progress":{"best_total_reps_last":120,"best_total_reps_prev":120,"delta":0,"improved":false,"pct_of_target":100},"master":false,"ready":true,"streak":2,"required_streak":2,"flags":[],"in_program":true,"program_exercises":[{"day":"Upper Push","exercise":"CC leg raise ladder - step 1 Knee tuck","step":1,"sets":2,"reps":"8-15"}],"last_event":null,"sessions":[{"workout_id":"qa-lgr-2","session_date":"2026-09-29","program_day":null,"title":null,"exercise":"Knee tuck","step":1,"sets":[{"set_order":1,"reps":40,"rir":null,"load_lb":0},{"set_order":2,"reps":40,"rir":null,"load_lb":0},{"set_order":3,"reps":40,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":true,"flags":[],"total_reps":120,"pct_of_target":100},{"workout_id":"qa-lgr-1","session_date":"2026-09-22","program_day":null,"title":null,"exercise":"Knee tuck","step":1,"sets":[{"set_order":1,"reps":40,"rir":null,"load_lb":0},{"set_order":2,"reps":40,"rir":null,"load_lb":0},{"set_order":3,"reps":40,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":true,"flags":[],"total_reps":120,"pct_of_target":100}],"steps":[
        {"step":1,"name":"Knee tuck","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":2,"name":"Flat knee raise","target_sets":3,"target_reps":35,"target_hold_sec":null,"target_label":"3×35"},
        {"step":3,"name":"Flat bent-leg raise","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Flat frog raise","target_sets":3,"target_reps":15,"target_hold_sec":null,"target_label":"3×15"},
        {"step":5,"name":"Flat straight-leg raise","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":6,"name":"Hanging knee raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":7,"name":"Hanging bent-leg raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":8,"name":"Hanging frog raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":9,"name":"Partial hanging straight-leg raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":10,"name":"Hanging straight-leg raise","target_sets":2,"target_reps":30,"target_hold_sec":null,"target_label":"2×30"}]},
      {"series":"PSH","label":"Push-up","current_step":1,"step_name":"Wall push-up","since":"2026-09-15T04:00:00.000Z","target_reps":50,"target_sets":3,"target_hold_sec":null,"target_label":"3×50","progress":null,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[],"steps":[
        {"step":1,"name":"Wall push-up","target_sets":3,"target_reps":50,"target_hold_sec":null,"target_label":"3×50"},
        {"step":2,"name":"Incline push-up","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":3,"name":"Kneeling push-up","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Half push-up","target_sets":2,"target_reps":25,"target_hold_sec":null,"target_label":"2×25"},
        {"step":5,"name":"Full push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":6,"name":"Close push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":7,"name":"Uneven push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":8,"name":"Half one-arm push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":9,"name":"Lever push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":10,"name":"One-arm push-up","target_sets":1,"target_reps":100,"target_hold_sec":null,"target_label":"1×100"}]},
      {"series":"PLL","label":"Pull-up","current_step":1,"step_name":"Vertical pull","since":"2026-09-15T04:00:00.000Z","target_reps":40,"target_sets":3,"target_hold_sec":null,"target_label":"3×40","progress":null,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[],"steps":[
        {"step":1,"name":"Vertical pull","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":2,"name":"Horizontal pull","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":3,"name":"Jackknife pull","target_sets":3,"target_reps":20,"target_hold_sec":null,"target_label":"3×20"},
        {"step":4,"name":"Half pull-up","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":5,"name":"Full pull-up","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":6,"name":"Close pull-up","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":7,"name":"Uneven pull-up","target_sets":2,"target_reps":9,"target_hold_sec":null,"target_label":"2×9"},
        {"step":8,"name":"Half one-arm pull-up","target_sets":2,"target_reps":8,"target_hold_sec":null,"target_label":"2×8"},
        {"step":9,"name":"Assisted one-arm pull-up","target_sets":2,"target_reps":7,"target_hold_sec":null,"target_label":"2×7"},
        {"step":10,"name":"One-arm pull-up","target_sets":2,"target_reps":6,"target_hold_sec":null,"target_label":"2×6"}]},
      {"series":"BRG","label":"Bridge","current_step":1,"step_name":"Short bridge","since":"2026-09-15T04:00:00.000Z","target_reps":50,"target_sets":3,"target_hold_sec":null,"target_label":"3×50","progress":{"best_total_reps_last":40,"best_total_reps_prev":null,"delta":null,"improved":false,"pct_of_target":26.7},"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":true,"program_exercises":[{"day":"Upper Physique","exercise":"CC bridge ladder - step 1 Short bridge","step":1,"sets":2,"reps":"8-15"}],"last_event":null,"sessions":[{"workout_id":"qa-brg-1","session_date":"2026-09-21","program_day":null,"title":null,"exercise":"Short bridge","step":1,"sets":[{"set_order":1,"reps":20,"rir":null,"load_lb":0},{"set_order":2,"reps":20,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["reps_below_target"],"total_reps":40,"pct_of_target":26.7}],"steps":[
        {"step":1,"name":"Short bridge","target_sets":3,"target_reps":50,"target_hold_sec":null,"target_label":"3×50"},
        {"step":2,"name":"Straight bridge","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":3,"name":"Angled bridge","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Head bridge","target_sets":2,"target_reps":25,"target_hold_sec":null,"target_label":"2×25"},
        {"step":5,"name":"Half bridge","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":6,"name":"Full bridge","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":7,"name":"Wall-walk bridge (down)","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":8,"name":"Wall-walk bridge (up)","target_sets":2,"target_reps":8,"target_hold_sec":null,"target_label":"2×8"},
        {"step":9,"name":"Closing bridge","target_sets":2,"target_reps":6,"target_hold_sec":null,"target_label":"2×6"},
        {"step":10,"name":"Stand-to-stand bridge","target_sets":2,"target_reps":30,"target_hold_sec":null,"target_label":"2×30"}]}
     ]}
    """#

    /// Same payload in bridge order (PSH, SQT, PLL, LGR, BRG, HSP).
    static let ccLaddersJSON = #"""
    {"generated_at":"2026-09-30T12:29:09.967Z",
     "rule":{"description":"A session qualifies when it reaches the step graduate-at target. Ready after 2 consecutive qualifying sessions.","required_streak":2,"master_step":10,"targets_by_series":{"PSH":{"1":{"sets":3,"reps":50,"hold_sec":null,"label":"3×50"},"2":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":2,"reps":25,"hold_sec":null,"label":"2×25"},"5":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"6":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"7":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"8":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"9":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"10":{"sets":1,"reps":100,"hold_sec":null,"label":"1×100"}},"SQT":{"1":{"sets":3,"reps":50,"hold_sec":null,"label":"3×50"},"2":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":2,"reps":50,"hold_sec":null,"label":"2×50"},"5":{"sets":2,"reps":30,"hold_sec":null,"label":"2×30"},"6":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"7":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"8":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"9":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"10":{"sets":2,"reps":50,"hold_sec":null,"label":"2×50"}},"PLL":{"1":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"2":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"3":{"sets":3,"reps":20,"hold_sec":null,"label":"3×20"},"4":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"5":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"6":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"7":{"sets":2,"reps":9,"hold_sec":null,"label":"2×9"},"8":{"sets":2,"reps":8,"hold_sec":null,"label":"2×8"},"9":{"sets":2,"reps":7,"hold_sec":null,"label":"2×7"},"10":{"sets":2,"reps":6,"hold_sec":null,"label":"2×6"}},"LGR":{"1":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"2":{"sets":3,"reps":35,"hold_sec":null,"label":"3×35"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":3,"reps":15,"hold_sec":null,"label":"3×15"},"5":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"6":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"7":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"8":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"9":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"10":{"sets":2,"reps":30,"hold_sec":null,"label":"2×30"}},"BRG":{"1":{"sets":3,"reps":50,"hold_sec":null,"label":"3×50"},"2":{"sets":3,"reps":40,"hold_sec":null,"label":"3×40"},"3":{"sets":3,"reps":30,"hold_sec":null,"label":"3×30"},"4":{"sets":2,"reps":25,"hold_sec":null,"label":"2×25"},"5":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"6":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"7":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"8":{"sets":2,"reps":8,"hold_sec":null,"label":"2×8"},"9":{"sets":2,"reps":6,"hold_sec":null,"label":"2×6"},"10":{"sets":2,"reps":30,"hold_sec":null,"label":"2×30"}},"HSP":{"1":{"sets":1,"reps":null,"hold_sec":120,"label":"2:00 hold"},"2":{"sets":1,"reps":null,"hold_sec":60,"label":"1:00 hold"},"3":{"sets":1,"reps":null,"hold_sec":120,"label":"2:00 hold"},"4":{"sets":2,"reps":20,"hold_sec":null,"label":"2×20"},"5":{"sets":2,"reps":15,"hold_sec":null,"label":"2×15"},"6":{"sets":2,"reps":12,"hold_sec":null,"label":"2×12"},"7":{"sets":2,"reps":10,"hold_sec":null,"label":"2×10"},"8":{"sets":2,"reps":8,"hold_sec":null,"label":"2×8"},"9":{"sets":2,"reps":6,"hold_sec":null,"label":"2×6"},"10":{"sets":2,"reps":5,"hold_sec":null,"label":"2×5"}}}},
     "active_program":{"id":"qa-program","name":"Program V2","version":3},
     "series":[
      {"series":"PSH","label":"Push-up","current_step":1,"step_name":"Wall push-up","since":"2026-09-15T04:00:00.000Z","target_reps":50,"target_sets":3,"target_hold_sec":null,"target_label":"3×50","progress":null,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[],"steps":[
        {"step":1,"name":"Wall push-up","target_sets":3,"target_reps":50,"target_hold_sec":null,"target_label":"3×50"},
        {"step":2,"name":"Incline push-up","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":3,"name":"Kneeling push-up","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Half push-up","target_sets":2,"target_reps":25,"target_hold_sec":null,"target_label":"2×25"},
        {"step":5,"name":"Full push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":6,"name":"Close push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":7,"name":"Uneven push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":8,"name":"Half one-arm push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":9,"name":"Lever push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":10,"name":"One-arm push-up","target_sets":1,"target_reps":100,"target_hold_sec":null,"target_label":"1×100"}]},
      {"series":"SQT","label":"Squat","current_step":2,"step_name":"Jackknife squat","since":"2026-09-15T04:00:00.000Z","target_reps":40,"target_sets":3,"target_hold_sec":null,"target_label":"3×40","progress":{"best_total_reps_last":52,"best_total_reps_prev":46,"delta":6,"improved":true,"pct_of_target":43.3},"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":true,"program_exercises":[{"day":"Lower B + Cond","exercise":"CC squat ladder - step 2 Jackknife squat","step":2,"sets":2,"reps":"8-15"}],"last_event":null,"sessions":[{"workout_id":"qa-sqt-2","session_date":"2026-09-29","program_day":null,"title":null,"exercise":"Jackknife squat","step":2,"sets":[{"set_order":1,"reps":18,"rir":null,"load_lb":0},{"set_order":2,"reps":17,"rir":null,"load_lb":0},{"set_order":3,"reps":17,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["rep_progress","reps_below_target"],"total_reps":52,"pct_of_target":43.3},{"workout_id":"qa-sqt-1","session_date":"2026-09-26","program_day":null,"title":null,"exercise":"Jackknife squat","step":2,"sets":[{"set_order":1,"reps":16,"rir":null,"load_lb":0},{"set_order":2,"reps":15,"rir":null,"load_lb":0},{"set_order":3,"reps":15,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["reps_below_target"],"total_reps":46,"pct_of_target":38.3}],"steps":[
        {"step":1,"name":"Shoulderstand squat","target_sets":3,"target_reps":50,"target_hold_sec":null,"target_label":"3×50"},
        {"step":2,"name":"Jackknife squat","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":3,"name":"Supported squat","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Half squat","target_sets":2,"target_reps":50,"target_hold_sec":null,"target_label":"2×50"},
        {"step":5,"name":"Full squat","target_sets":2,"target_reps":30,"target_hold_sec":null,"target_label":"2×30"},
        {"step":6,"name":"Close squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":7,"name":"Uneven squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":8,"name":"Half one-leg squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":9,"name":"Assisted one-leg squat","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":10,"name":"One-leg squat (pistol)","target_sets":2,"target_reps":50,"target_hold_sec":null,"target_label":"2×50"}]},
      {"series":"PLL","label":"Pull-up","current_step":1,"step_name":"Vertical pull","since":"2026-09-15T04:00:00.000Z","target_reps":40,"target_sets":3,"target_hold_sec":null,"target_label":"3×40","progress":null,"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[],"steps":[
        {"step":1,"name":"Vertical pull","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":2,"name":"Horizontal pull","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":3,"name":"Jackknife pull","target_sets":3,"target_reps":20,"target_hold_sec":null,"target_label":"3×20"},
        {"step":4,"name":"Half pull-up","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":5,"name":"Full pull-up","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":6,"name":"Close pull-up","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":7,"name":"Uneven pull-up","target_sets":2,"target_reps":9,"target_hold_sec":null,"target_label":"2×9"},
        {"step":8,"name":"Half one-arm pull-up","target_sets":2,"target_reps":8,"target_hold_sec":null,"target_label":"2×8"},
        {"step":9,"name":"Assisted one-arm pull-up","target_sets":2,"target_reps":7,"target_hold_sec":null,"target_label":"2×7"},
        {"step":10,"name":"One-arm pull-up","target_sets":2,"target_reps":6,"target_hold_sec":null,"target_label":"2×6"}]},
      {"series":"LGR","label":"Leg raise","current_step":1,"step_name":"Knee tuck","since":"2026-09-15T04:00:00.000Z","target_reps":40,"target_sets":3,"target_hold_sec":null,"target_label":"3×40","progress":{"best_total_reps_last":120,"best_total_reps_prev":120,"delta":0,"improved":false,"pct_of_target":100},"master":false,"ready":true,"streak":2,"required_streak":2,"flags":[],"in_program":true,"program_exercises":[{"day":"Upper Push","exercise":"CC leg raise ladder - step 1 Knee tuck","step":1,"sets":2,"reps":"8-15"}],"last_event":null,"sessions":[{"workout_id":"qa-lgr-2","session_date":"2026-09-29","program_day":null,"title":null,"exercise":"Knee tuck","step":1,"sets":[{"set_order":1,"reps":40,"rir":null,"load_lb":0},{"set_order":2,"reps":40,"rir":null,"load_lb":0},{"set_order":3,"reps":40,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":true,"flags":[],"total_reps":120,"pct_of_target":100},{"workout_id":"qa-lgr-1","session_date":"2026-09-22","program_day":null,"title":null,"exercise":"Knee tuck","step":1,"sets":[{"set_order":1,"reps":40,"rir":null,"load_lb":0},{"set_order":2,"reps":40,"rir":null,"load_lb":0},{"set_order":3,"reps":40,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":true,"flags":[],"total_reps":120,"pct_of_target":100}],"steps":[
        {"step":1,"name":"Knee tuck","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":2,"name":"Flat knee raise","target_sets":3,"target_reps":35,"target_hold_sec":null,"target_label":"3×35"},
        {"step":3,"name":"Flat bent-leg raise","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Flat frog raise","target_sets":3,"target_reps":15,"target_hold_sec":null,"target_label":"3×15"},
        {"step":5,"name":"Flat straight-leg raise","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":6,"name":"Hanging knee raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":7,"name":"Hanging bent-leg raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":8,"name":"Hanging frog raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":9,"name":"Partial hanging straight-leg raise","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":10,"name":"Hanging straight-leg raise","target_sets":2,"target_reps":30,"target_hold_sec":null,"target_label":"2×30"}]},
      {"series":"BRG","label":"Bridge","current_step":1,"step_name":"Short bridge","since":"2026-09-15T04:00:00.000Z","target_reps":50,"target_sets":3,"target_hold_sec":null,"target_label":"3×50","progress":{"best_total_reps_last":40,"best_total_reps_prev":null,"delta":null,"improved":false,"pct_of_target":26.7},"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":true,"program_exercises":[{"day":"Upper Physique","exercise":"CC bridge ladder - step 1 Short bridge","step":1,"sets":2,"reps":"8-15"}],"last_event":null,"sessions":[{"workout_id":"qa-brg-1","session_date":"2026-09-21","program_day":null,"title":null,"exercise":"Short bridge","step":1,"sets":[{"set_order":1,"reps":20,"rir":null,"load_lb":0},{"set_order":2,"reps":20,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["reps_below_target"],"total_reps":40,"pct_of_target":26.7}],"steps":[
        {"step":1,"name":"Short bridge","target_sets":3,"target_reps":50,"target_hold_sec":null,"target_label":"3×50"},
        {"step":2,"name":"Straight bridge","target_sets":3,"target_reps":40,"target_hold_sec":null,"target_label":"3×40"},
        {"step":3,"name":"Angled bridge","target_sets":3,"target_reps":30,"target_hold_sec":null,"target_label":"3×30"},
        {"step":4,"name":"Head bridge","target_sets":2,"target_reps":25,"target_hold_sec":null,"target_label":"2×25"},
        {"step":5,"name":"Half bridge","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":6,"name":"Full bridge","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":7,"name":"Wall-walk bridge (down)","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":8,"name":"Wall-walk bridge (up)","target_sets":2,"target_reps":8,"target_hold_sec":null,"target_label":"2×8"},
        {"step":9,"name":"Closing bridge","target_sets":2,"target_reps":6,"target_hold_sec":null,"target_label":"2×6"},
        {"step":10,"name":"Stand-to-stand bridge","target_sets":2,"target_reps":30,"target_hold_sec":null,"target_label":"2×30"}]},
      {"series":"HSP","label":"Handstand push-up","current_step":1,"step_name":"Wall headstand","since":"2026-09-15T04:00:00.000Z","target_reps":null,"target_sets":1,"target_hold_sec":120,"target_label":"2:00 hold","progress":{"best_total_reps_last":75,"best_total_reps_prev":60,"delta":15,"improved":true,"pct_of_target":62.5},"master":false,"ready":false,"streak":0,"required_streak":2,"flags":[],"in_program":false,"program_exercises":[],"last_event":null,"sessions":[{"workout_id":"qa-hsp-2","session_date":"2026-09-28","program_day":null,"title":null,"exercise":"Wall headstand","step":1,"sets":[{"set_order":1,"reps":75,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["rep_progress","hold_below_target"],"total_reps":75,"pct_of_target":62.5},{"workout_id":"qa-hsp-1","session_date":"2026-09-25","program_day":null,"title":null,"exercise":"Wall headstand","step":1,"sets":[{"set_order":1,"reps":60,"rir":null,"load_lb":0}],"counts_toward_current_step":true,"qualifying":false,"flags":["hold_below_target"],"total_reps":60,"pct_of_target":50}],"steps":[
        {"step":1,"name":"Wall headstand","target_sets":1,"target_reps":null,"target_hold_sec":120,"target_label":"2:00 hold"},
        {"step":2,"name":"Crow stand","target_sets":1,"target_reps":null,"target_hold_sec":60,"target_label":"1:00 hold"},
        {"step":3,"name":"Wall handstand","target_sets":1,"target_reps":null,"target_hold_sec":120,"target_label":"2:00 hold"},
        {"step":4,"name":"Half handstand push-up","target_sets":2,"target_reps":20,"target_hold_sec":null,"target_label":"2×20"},
        {"step":5,"name":"Handstand push-up","target_sets":2,"target_reps":15,"target_hold_sec":null,"target_label":"2×15"},
        {"step":6,"name":"Close handstand push-up","target_sets":2,"target_reps":12,"target_hold_sec":null,"target_label":"2×12"},
        {"step":7,"name":"Uneven handstand push-up","target_sets":2,"target_reps":10,"target_hold_sec":null,"target_label":"2×10"},
        {"step":8,"name":"Half one-arm handstand push-up","target_sets":2,"target_reps":8,"target_hold_sec":null,"target_label":"2×8"},
        {"step":9,"name":"Lever handstand push-up","target_sets":2,"target_reps":6,"target_hold_sec":null,"target_label":"2×6"},
        {"step":10,"name":"One-arm handstand push-up","target_sets":2,"target_reps":5,"target_hold_sec":null,"target_label":"2×5"}]}
     ]}
    """#

    /// Path -> (status, body). Built on the main actor before any request is made.
    static func buildResponses() -> [String: (Int, Data)] {
        let encoder = JSONEncoder()
        func json<T: Encodable>(_ value: T) -> (Int, Data) {
            ((try? encoder.encode(value)).map { (200, $0) }) ?? (500, Data())
        }
        let program = TrainingProgramRecord.bundledV2()
        return [
            "/api/workouts": json(ListWorkoutsResponse(workouts: sampleWorkouts())),
            "/api/workouts/\(workoutID)": json(sampleWorkoutDetail()),
            "/api/workouts/\(upperPhysiqueWorkoutID)": json(upperPhysiqueWorkoutDetail()),
            "/api/programs": json(TrainingProgramListResponse(programs: [program])),
            "/api/programs/active": json(program),
            "/api/programs/\(program.id)": json(program),
            "/api/peptides/today": (200, Data(peptideTodayJSON().utf8)),
            "/api/peptides/inventory": (200, Data(peptideInventoryJSON.utf8)),
            "/api/peptides/schedules": (200, Data(peptideSchedulesJSON.utf8)),
            "/api/peptides/administrations": (200, peptideAdministrationsJSON()),
            "/api/cc/ladders": (200, Data((ccLaddersJSONOverride ?? ccLaddersJSON).utf8)),
        ]
    }
}

/// Thread-safe holder the URLProtocol reads from URLSession's queue.
nonisolated final class VisualQAStubStorage: @unchecked Sendable {
    static let host = "visual-qa.invalid"
    /// Fake bridge key for Visual QA only. Peptide routes answer 401 without it.
    static let bridgeKey = "visual-qa-bridge-key"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: (Int, Data)] = [:]

    static func setResponses(_ value: [String: (Int, Data)]) {
        lock.lock(); defer { lock.unlock() }
        responses = value
    }

    static func response(for request: URLRequest) -> (Int, Data) {
        guard (request.httpMethod ?? "GET") == "GET" else {
            return (405, Data(#"{"error":"visual_qa_read_only"}"#.utf8))
        }
        let path = request.url?.path ?? ""
        if path.hasPrefix("/api/peptides/"),
           request.value(forHTTPHeaderField: "Authorization") != "Bearer \(bridgeKey)" {
            return (401, Data(#"{"error":"unauthorized"}"#.utf8))
        }
        lock.lock(); defer { lock.unlock() }
        return responses[path] ?? (404, Data(#"{"error":"not_found"}"#.utf8))
    }
}

/// Answers bridge requests from fixtures so snapshot runs never touch the real bridge.
nonisolated final class VisualQAStubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == VisualQAStubStorage.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let (status, data) = VisualQAStubStorage.response(for: request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://\(VisualQAStubStorage.host)")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Build 62 (additive, human-owned goldens-update)

extension VisualQASnapshotTests {
    func test70LoggerSetRows() async throws {
        try await build62Shot("70-logger-set-rows", heightMultiplier: 3.4, scenario: .rows)
    }

    func test71RestNextSet() async throws {
        try await build62Shot("71-rest-next-set", heightMultiplier: 2.4, scenario: .nextSet)
    }

    func test72LoggerReorder() async throws {
        try await build62Shot("72-logger-reorder", heightMultiplier: 5, scenario: .reorder)
    }

    func test73PreExhaustionNote() async throws {
        try await build62Shot("73-pre-exhaustion-note", heightMultiplier: 8, scenario: .preExhaustion)
        // An explicit Add Set after the three performed sets exposes the
        // within-session HOLD decision on the real rest next-set card.
        try await build62Shot("73b-pre-exhaustion-hold", heightMultiplier: 2.4, scenario: .preExhaustionNextSet)
    }

    func test74Week3Day2() async throws {
        try await build62Shot("74-week3-day2", heightMultiplier: 8, scenario: .week3Day2)
    }

    func test75Week3Day3() async throws {
        try await build62Shot("75-week3-day3", heightMultiplier: 6, scenario: .week3Day3)
    }

    func test76ReductionWeekDay() async throws {
        try await build62Shot("76-reduction-week-day", heightMultiplier: 8, scenario: .reduction)
    }

    func test77RestBar() async throws {
        try await build62Shot("77-rest-bar", heightMultiplier: 3.4, scenario: .restBar)
    }

    // 78-undo-toast is intentionally not added: the five-second wall-clock Undo toast
    // can expire while the existing snapshot renderer waits for presentation
    // and loaders. Do not extend its expiry to manufacture a stable image.

    private func build62Shot(_ name: String, heightMultiplier: CGFloat,
                             scenario: VisualQABuild62Fixture.Scenario) async throws {
        // Tall build-62 renders reach ~21k px on the Pro simulator; the 2-minute default
        // allowance timed out test74 there in run 37165562250. CI caps this at 240 s.
        executionTimeAllowance = 240
        var fixture: VisualQABuild62Fixture?
        try await eachSize(name, heightMultiplier: heightMultiplier, sheet: {
            let seeded = VisualQABuild62Fixture(scenario: scenario)
            fixture = seeded
            seeded.assertScenario()
            VisualQAGraveyard.keep(seeded, seeded.drafts, seeded.entry, seeded.rest)
            return ProgramV2WorkoutLogView(visualQAEntry: seeded.entry,
                restSession: seeded.rest, openedAt: seeded.date,
                initiallyReordering: scenario == .reorder)
                .environment(seeded.drafts)
        }, secondSheet: [.nextSet, .preExhaustionNextSet].contains(scenario) ? {
            // eachSize constructs the logger sheet first, then this sheet.
            // Both surfaces share the same real entry/rest owner objects.
            guard let seeded = fixture else {
                XCTFail("Missing build-62 logger fixture")
                return AnyView(EmptyView())
            }
            return AnyView(NavigationStack {
                RestTimerSheet(session: seeded.rest,
                    next: seeded.entry.restDetails(in: seeded.drafts, isHold: false),
                    onChange: { seeded.entry.editNext($0) },
                    onStep: { seeded.entry.stepNext(load: $0, direction: $1, isHold: false) },
                    onLog: { seeded.entry.logNext(in: seeded.drafts, startedAt: seeded.date, rest: seeded.rest) },
                    onSkip: { seeded.entry.skipNext(in: seeded.drafts, rest: seeded.rest) })
            })
        } : nil) { _ in
            // install() has already registered the existing read-only protocol.
            // Override only this new scenario's responses, independently per size.
            VisualQAStubStorage.setResponses(VisualQAFixtures.build62Responses())
            return VisualQATabShell(selected: .train) {
                JLPhysicalTabView(referenceDate: scenario.date)
            }
        }
    }
}

@MainActor
extension VisualQAFixtures {
    /// Bundled V3 plus the documented live V4 arm prescriptions. Bridge RIR
    /// lives in notes, so these images exercise the real notes fallback too.
    static func build62Body() -> TrainingProgramBody {
        var body = TrainingProgramBody.bundledV2()
        body.startDate = "2026-09-28"
        body.reductionWeek = 4
        body.days[1].exercises[4].order = 5
        body.days[1].exercises.append(TrainingProgramExercise(order: 4,
            name: "Overhead triceps extension (cable or DB)", sets: 2,
            reps: "10-15", restSec: 60, loadNote: "Start 25 lb",
            notes: "Rest: 60-75 s. RIR target: 1-2 RIR."))
        if let index = body.days[2].exercises.firstIndex(where: { $0.name == "Cable or DB curl" }) {
            body.days[2].exercises[index].sets = 3
        }
        for dayIndex in body.days.indices {
            for exerciseIndex in body.days[dayIndex].exercises.indices {
                let target = body.days[dayIndex].exercises[exerciseIndex].rir
                if !target.isEmpty {
                    let notes = body.days[dayIndex].exercises[exerciseIndex].notes ?? ""
                    body.days[dayIndex].exercises[exerciseIndex].notes = "\(notes) RIR target: \(target)."
                    body.days[dayIndex].exercises[exerciseIndex].rir = ""
                }
            }
        }
        return body
    }

    static func build62History() -> [WorkoutDetailResponse] {
        let body = build62Body()
        return body.days.prefix(3).map { day in
            let workout = RemoteWorkout(id: "qa-build62-day\(day.dayIndex)", kind: "COMPLETED",
                programVersion: "program-v2", programDay: day.asProgramV2Day().id,
                title: day.name, units: "lb", sessionDate: "2026-09-29",
                conditioning: nil, notes: [], contentHash: nil, synthetic: false, recordedAt: nil)
            let sets = day.exercises.sorted { $0.order < $1.order }.enumerated().map { index, exercise in
                RemoteWorkoutSet(id: "qa-build62-\(day.dayIndex)-\(index)", workoutId: workout.id,
                    setOrder: index + 1, exercise: exercise.name,
                    loadLb: exercise.name == "Chest press machine" ? 87.5 : exercise.parsedStartLoadLb ?? 25,
                    reps: 12, rir: 2, rpe: nil)
            }
            return WorkoutDetailResponse(workout: workout, sets: sets)
        }
    }

    static func build62Responses() -> [String: (Int, Data)] {
        var responses = buildResponses()
        let encoder = JSONEncoder()
        func json<T: Encodable>(_ value: T) -> (Int, Data) {
            do { return (200, try encoder.encode(value)) }
            catch { XCTFail("Could not encode build-62 bridge fixture: \(error)"); return (500, Data()) }
        }
        var program = TrainingProgramRecord.bundledV2()
        program.body = build62Body()
        let history = build62History()
        responses["/api/programs"] = json(TrainingProgramListResponse(programs: [program]))
        responses["/api/programs/active"] = json(program)
        responses["/api/programs/\(program.id)"] = json(program)
        responses["/api/workouts"] = json(ListWorkoutsResponse(workouts: history.map(\.workout)))
        for detail in history { responses["/api/workouts/\(detail.workout.id)"] = json(detail) }
        return responses
    }
}

/// Per-render fixtures use the existing models and persistence, with no mock
/// timer driver. Pausing a driverless RestSession freezes both visible clocks.
@MainActor
final class VisualQABuild62Fixture {
    enum Scenario: Equatable {
        case rows, nextSet, reorder, preExhaustion, preExhaustionNextSet, week3Day2, week3Day3, reduction, restBar

        var date: Date {
            let civilDay: String
            switch self {
            case .week3Day2: civilDay = "2026-10-13"
            case .week3Day3: civilDay = "2026-10-14"
            case .reduction: civilDay = "2026-10-20"
            case .preExhaustion, .preExhaustionNextSet: civilDay = "2026-09-29"
            default: civilDay = "2026-10-05"
            }
            return SessionDateFormatting.date(from: civilDay, calendar: ProgramWeekRules.easternCalendar)!
        }

        var dayIndex: Int {
            switch self {
            case .preExhaustion, .preExhaustionNextSet, .week3Day2, .reduction: 2
            case .week3Day3: 3
            default: 1
            }
        }
    }

    let scenario: Scenario
    let date: Date
    let day: ProgramV2Day
    let drafts: WorkoutDraftStore
    let entry: WorkoutSetEntry
    let rest: RestSession

    init(scenario: Scenario) {
        self.scenario = scenario
        date = scenario.date
        let body = VisualQAFixtures.build62Body()
        // This is the same dated builder used by Train's Start Workout path.
        var day = body.programV2Day(for: body.days[scenario.dayIndex - 1], on: scenario.date)
        if [.rows, .nextSet, .restBar].contains(scenario) {
            day.exercises = Array(day.exercises.prefix(1))
        }
        self.day = day
        drafts = WorkoutDraftStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("visual-qa-build62-\(UUID().uuidString)", isDirectory: true))
        entry = WorkoutSetEntry(day: day)
        entry.lastPerformances = LastPerformanceBuilder.build(from: VisualQAFixtures.build62History(),
            preferredProgramDay: day.id)
        let fixedDate = scenario.date
        rest = RestSession(initiallyMuted: true, now: { fixedDate })

        switch scenario {
        case .rows, .nextSet, .restBar:
            let exercise = day.exercises[0]
            let row = LoggedSet(weight: scenario == .rows ? 150 : 145, reps: scenario == .rows ? 12 : 15,
                                rir: scenario == .rows ? 2 : 4, rpeText: "")
            drafts.update(day, startedAt: date) { draft in
                draft.conditioningCompleted = true
                draft.sets[exercise.name] = [row]
            }
            entry.editingStep = ExerciseStep(exerciseName: exercise.name, setIndex: 1)
            if scenario != .rows {
                entry.startRestAfterLogging(exercise, at: 0, in: drafts, rest: rest)
                rest.pause()
            }
        case .preExhaustion, .preExhaustionNextSet:
            let press = day.exercises.first { $0.name == "Chest press machine" }!
            // Use the real block-move API until the anchor is last.
            while let block = entry.order(in: drafts).blocks.first(where: { $0.exercises.contains { $0.name == press.name } }),
                  entry.canMove(block, direction: .down, in: drafts) {
                entry.move(block, direction: .down, in: drafts, startedAt: date, rest: rest)
            }
            drafts.update(day, startedAt: date) { draft in
                draft.conditioningCompleted = true
                for exercise in day.exercises where exercise.name != press.name {
                    draft.sets[exercise.name] = (0..<exercise.sets).map { _ in
                        LoggedSet(weight: exercise.startLoadLb ?? 25, reps: 12, rir: 2, rpeText: "")
                    }
                }
                draft.sets[press.name] = [
                    LoggedSet(weight: 87.5, reps: 12, rir: 2, rpeText: ""),
                    LoggedSet(weight: 87.5, reps: 12, rir: 1, rpeText: ""),
                    LoggedSet(weight: 87.5, reps: 9, rir: 0, rpeText: ""),
                ]
            }
            if scenario == .preExhaustionNextSet {
                entry.add(press, in: drafts, startedAt: date)
                entry.startRestAfterLogging(press, at: 2, in: drafts, rest: rest)
                rest.pause()
            }
        case .reorder, .week3Day2, .week3Day3, .reduction:
            break
        }
    }

    func assertScenario() {
        switch scenario {
        case .rows:
            let exercise = day.exercises[0]
            XCTAssertEqual(drafts.draft?.loggedSetCount, 1)
            XCTAssertEqual(entry.editingStep?.setIndex, 1)
            XCTAssertEqual(SetEntryLogic.targetChips(for: exercise, at: 1), [2, 3])
            XCTAssertEqual(SetEntryLogic.plannedRowCount(exercise: exercise,
                sets: drafts.draft?.sets[exercise.name] ?? []), 3)
            XCTAssertTrue(SetEntryLogic.isPersonalRecord(set: drafts.draft!.sets[exercise.name]![0],
                previous: entry.lastPerformance(for: exercise)))
        case .nextSet, .restBar:
            let next = entry.restDetails(in: drafts, isHold: false)
            XCTAssertEqual(next?.step.setIndex, 1)
            XCTAssertEqual(next?.value.weight, 150)
            XCTAssertEqual(next?.reason, "+5: hit 15 @ RIR 4")
            XCTAssertEqual(next?.reference, "Today S1 145 × 15 @ RIR 4 · Last time 145 × 12 @ 2")
            XCTAssertTrue(rest.isPaused)
            XCTAssertEqual(rest.formattedTime, "1:30")
        case .preExhaustion, .preExhaustionNextSet:
            let press = day.exercises.first { $0.name == "Chest press machine" }!
            XCTAssertEqual(entry.order(in: drafts).exerciseOrder.last, press.name)
            XCTAssertEqual(entry.preExhaustionNote(for: press, in: drafts),
                "Done later than planned · a miss holds the load")
            XCTAssertEqual(entry.prefill(for: press, at: 3, in: drafts).decision,
                ProgressionDecision(load: 87.5, reason: .holdPreFatigued))
            if scenario == .preExhaustionNextSet {
                let next = entry.restDetails(in: drafts, isHold: false)
                XCTAssertEqual(next?.step, ExerciseStep(exerciseName: press.name, setIndex: 3))
                XCTAssertEqual(next?.value.weight, 87.5)
                XCTAssertEqual(next?.reason, "Hold: done later than planned — not counted as a miss")
                XCTAssertTrue(rest.isPaused)
            }
        case .week3Day2:
            XCTAssertEqual(day.exercises.first { $0.name == "Overhead triceps extension (cable or DB)" }?.sets, 3)
            XCTAssertEqual(day.weekNote, "Week 3: +1 set on overhead extension (if elbows feel good)")
        case .week3Day3:
            XCTAssertEqual(day.exercises.first { $0.name == "Cable or DB curl" }?.sets, 4)
            XCTAssertEqual(day.weekNote, "Week 3: +1 set on curl (if elbows feel good)")
        case .reduction:
            XCTAssertTrue(day.holdLoads)
            XCTAssertEqual(day.exercises.first { $0.name == "Chest press machine" }?.sets, 2)
            XCTAssertEqual(day.exercises.first { $0.name == "Overhead triceps extension (cable or DB)" }?.setsLabel, "1–2")
            XCTAssertEqual(day.exercises.first { CCLadderLogic.isLadderExerciseName($0.name) }?.sets, 1)
            XCTAssertTrue(day.exercises.allSatisfy { $0.rirTarget == "3-4 RIR" })
        case .reorder:
            let middle = entry.order(in: drafts).blocks[1]
            XCTAssertTrue(entry.canMove(middle, direction: .up, in: drafts))
            XCTAssertTrue(entry.canMove(middle, direction: .down, in: drafts))
        }
    }
}

// MARK: - Build 65: CC ladder form sheet (additive, human-owned goldens-update)

/// Shots 85-94: the step form sheet over a plain canvas, default + axL. Steps
/// are stub bridge data copied from lib/cc.ts CC_LADDERS, so nothing hits the
/// network. Ladders without bundled art yet show the SF Symbol placeholder.
extension VisualQASnapshotTests {
    func test85CCForm_SQT03() async throws {
        try await ccFormShot("85-ccform-sqt03", series: "SQT", step: 3)
    }

    func test86CCForm_PSH01() async throws {
        try await ccFormShot("86-ccform-psh01", series: "PSH", step: 1)
    }

    func test87CCForm_PSH10() async throws {
        try await ccFormShot("87-ccform-psh10", series: "PSH", step: 10)
    }

    func test88CCForm_PLL03() async throws {
        try await ccFormShot("88-ccform-pll03", series: "PLL", step: 3)
    }

    func test89CCForm_LGR02() async throws {
        try await ccFormShot("89-ccform-lgr02", series: "LGR", step: 2)
    }

    func test90CCForm_LGR06() async throws {
        try await ccFormShot("90-ccform-lgr06", series: "LGR", step: 6)
    }

    func test91CCForm_BRG01() async throws {
        try await ccFormShot("91-ccform-brg01", series: "BRG", step: 1)
    }

    func test92CCForm_BRG10() async throws {
        try await ccFormShot("92-ccform-brg10", series: "BRG", step: 10)
    }

    func test93CCForm_HSP01() async throws {
        try await ccFormShot("93-ccform-hsp01", series: "HSP", step: 1)
    }

    func test94CCForm_HSP10() async throws {
        try await ccFormShot("94-ccform-hsp10", series: "HSP", step: 10)
    }

    private func ccFormShot(_ name: String, series code: String, step: Int) async throws {
        let series = try XCTUnwrap(VisualQACCFormFixtures.series(code, currentStep: step), "No stub ladder \(code)")
        XCTAssertNotNil(CCLadderLogic.stepInfo(step, in: series))
        try await eachSize(name, heightMultiplier: 1.5, sheet: {
            CCStepFormSheet(series: series, rule: nil, step: step)
        }) { _ in
            IronTheme.canvas.ignoresSafeArea()
        }
    }
}

/// Stub CC ladders for the form sheet shots, matching lib/cc.ts CC_LADDERS.
@MainActor
enum VisualQACCFormFixtures {
    private struct Row {
        var name: String
        var bookName: String
        var pages: String?
        var sets: Int
        var reps: Int?
        var holdSec: Int?
    }

    private static func r(_ name: String, _ book: String, _ pages: String?, _ sets: Int, _ reps: Int) -> Row {
        Row(name: name, bookName: book, pages: pages, sets: sets, reps: reps, holdSec: nil)
    }

    private static func hold(_ name: String, _ book: String, _ pages: String?, _ seconds: Int) -> Row {
        Row(name: name, bookName: book, pages: pages, sets: 1, reps: nil, holdSec: seconds)
    }

    private static let ladders: [String: (label: String, rows: [Row])] = [
        "PSH": ("Push-up", [
            r("Wall push-up", "Wall Pushups", "46-47", 3, 50),
            r("Incline push-up", "Incline Pushups", "48-49", 3, 40),
            r("Kneeling push-up", "Kneeling Pushups", "50-51", 3, 30),
            r("Half push-up", "Half Pushups", "52-53", 2, 25),
            r("Full push-up", "Full Pushups", "54-55", 2, 20),
            r("Close push-up", "Close Pushups", "56-57", 2, 20),
            r("Uneven push-up", "Uneven Pushups", "58-59", 2, 20),
            r("Half one-arm push-up", "1/2 One-Arm Pushups", "60-61", 2, 20),
            r("Lever push-up", "Lever Pushups", "62-63", 2, 20),
            r("One-arm push-up", "One-Arm Pushups", "64-65", 1, 100),
        ]),
        "SQT": ("Squat", [
            r("Shoulderstand squat", "Shoulderstand Squats", "84-85", 3, 50),
            r("Jackknife squat", "Jackknife Squats", "86-87", 3, 40),
            r("Supported squat", "Supported Squats", "88-89", 3, 30),
            r("Half squat", "Half Squats", "90-91", 2, 50),
            r("Full squat", "Full Squats", "92-93", 2, 30),
            r("Close squat", "Close Squats", "94-95", 2, 20),
            r("Uneven squat", "Uneven Squats", "96-97", 2, 20),
            r("Half one-leg squat", "1/2 One-Leg Squats", "98-99", 2, 20),
            r("Assisted one-leg squat", "Assisted One-Leg Squats", "100-101", 2, 20),
            r("One-leg squat (pistol)", "One-Leg Squats", "102-103", 2, 50),
        ]),
        "PLL": ("Pull-up", [
            r("Vertical pull", "Vertical Pulls", "122-123", 3, 40),
            r("Horizontal pull", "Horizontal Pulls", "124-125", 3, 30),
            r("Jackknife pull", "Jackknife Pulls", "126-127", 3, 20),
            r("Half pull-up", "Half Pullups", "128-129", 2, 15),
            r("Full pull-up", "Full Pullups", "130-131", 2, 10),
            r("Close pull-up", "Close Pullups", "132-133", 2, 10),
            r("Uneven pull-up", "Uneven Pullups", "134-135", 2, 9),
            r("Half one-arm pull-up", "1/2 One-Arm Pullups", "136-137", 2, 8),
            r("Assisted one-arm pull-up", "Assisted One-Arm Pullups", "138-139", 2, 7),
            r("One-arm pull-up", "One-Arm Pullups", "140-141", 2, 6),
        ]),
        "LGR": ("Leg raise", [
            r("Knee tuck", "Knee Tucks", "156-157", 3, 40),
            r("Flat knee raise", "Flat Knee Raises", "158-159", 3, 35),
            r("Flat bent-leg raise", "Flat Bent Leg Raises", "160-161", 3, 30),
            r("Flat frog raise", "Flat Frog Raises", "162-163", 3, 15),
            r("Flat straight-leg raise", "Flat Straight Leg Raises", nil, 2, 20),
            r("Hanging knee raise", "Hanging Knee Raises", "166-167", 2, 15),
            r("Hanging bent-leg raise", "Hanging Bent Leg Raises", "168-169", 2, 15),
            r("Hanging frog raise", "Hanging Frog Raises", "170-171", 2, 15),
            r("Partial hanging straight-leg raise", "Partial Straight Leg Raises", "172-173", 2, 15),
            r("Hanging straight-leg raise", "Hanging Straight Leg Raises", "174-175", 2, 30),
        ]),
        "BRG": ("Bridge", [
            r("Short bridge", "Short Bridges", "194-195", 3, 50),
            r("Straight bridge", "Straight Bridges", "196-197", 3, 40),
            r("Angled bridge", "Angled Bridges", "198-199", 3, 30),
            r("Head bridge", "Head Bridges", "200-201", 2, 25),
            r("Half bridge", "Half Bridges", "202-203", 2, 20),
            r("Full bridge", "Full Bridges", "204-205", 2, 15),
            r("Wall-walk bridge (down)", "Wall Walking Bridges (Down)", "206-207", 2, 10),
            r("Wall-walk bridge (up)", "Wall Walking Bridges (Up)", "208-209", 2, 8),
            r("Closing bridge", "Closing Bridges", "210-211", 2, 6),
            r("Stand-to-stand bridge", "Stand-to-Stand Bridges", "212-213", 2, 30),
        ]),
        "HSP": ("Handstand push-up", [
            hold("Wall headstand", "Wall Headstands", "230-231", 120),
            hold("Crow stand", "Crow Stands", "232-233", 60),
            hold("Wall handstand", "Wall Handstands", "234-235", 120),
            r("Half handstand push-up", "Half Handstand Pushups", "236-237", 2, 20),
            r("Handstand push-up", "Handstand Pushups", "238-239", 2, 15),
            r("Close handstand push-up", "Close Handstand Pushups", "240-242", 2, 12),
            r("Uneven handstand push-up", "Uneven Handstand Pushups", "242-243", 2, 10),
            r("Half one-arm handstand push-up", "1/2 One-Arm Handstand Pushups", "244-245", 2, 8),
            r("Lever handstand push-up", "Lever Handstand Pushups", "246-247", 2, 6),
            r("One-arm handstand push-up", "One-Arm Handstand Pushups", "248-249", 2, 5),
        ]),
    ]

    static func series(_ code: String, currentStep: Int) -> CCSeriesState? {
        guard let ladder = ladders[code] else { return nil }
        let steps = ladder.rows.enumerated().map { index, row in
            CCLadderStep(
                step: index + 1,
                name: row.name,
                targetReps: row.reps,
                bookName: row.bookName,
                pages: row.pages,
                targetSets: row.sets,
                targetHoldSec: row.holdSec,
                targetLabel: nil
            )
        }
        return CCSeriesState(series: code, label: ladder.label, currentStep: currentStep, inProgram: true, steps: steps)
    }
}
