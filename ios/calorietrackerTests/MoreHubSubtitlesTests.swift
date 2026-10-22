import Foundation
import Testing
@testable import calorietracker

/// Pins the More hub subtitle wording now that it lives in MoreHubSubtitles.
@MainActor
struct MoreHubSubtitlesTests {
    private static let now = Date(timeIntervalSince1970: 1_791_378_000) // 2026-10-07 13:00 UTC

    private func inputs(
        programName: String? = "Program V2",
        healthKitEnabled: Bool = true,
        weightUnitRaw: String = "lbs",
        bridgeConfigured: Bool = true,
        iCloudEnabled: Bool = true,
        iCloudLastBackup: Date? = nil,
        notificationsMasterEnabled: Bool = true,
        enabledReminderCount: Int = 6
    ) -> MoreHubInputs {
        MoreHubInputs(
            programName: programName,
            defaultRestLabel: "1:30",
            foodModelName: "Gemini Flash",
            gemmaStatus: "Gemma off",
            healthKitEnabled: healthKitEnabled,
            weightUnitRaw: weightUnitRaw,
            bridgeConfigured: bridgeConfigured,
            iCloudEnabled: iCloudEnabled,
            iCloudLastBackupISO: iCloudLastBackup.map { ISO8601DateFormatter().string(from: $0) },
            notificationsMasterEnabled: notificationsMasterEnabled,
            enabledReminderCount: enabledReminderCount,
            appVersion: "1.0 (64)",
            now: Self.now
        )
    }

    @Test func trainingNamesTheProgramAndFallsBackToV2() {
        #expect(MoreHubSubtitles.text(for: .training, inputs(programName: "Block A")) == "Block A · rest 1:30")
        #expect(MoreHubSubtitles.text(for: .training, inputs(programName: nil)) == "Program V2 · rest 1:30")
    }

    @Test func foodAIShowsModelAndGemmaStatus() {
        #expect(MoreHubSubtitles.text(for: .foodAI, inputs()) == "Gemini Flash · Gemma off")
    }

    @Test func bodyHealthShowsHealthAndUnit() {
        #expect(MoreHubSubtitles.text(for: .bodyHealth, inputs()) == "Apple Health on · lb")
        #expect(MoreHubSubtitles.text(for: .bodyHealth, inputs(healthKitEnabled: false, weightUnitRaw: "kg"))
            == "Apple Health off · kg")
    }

    @Test func dataSyncCountsICloudAgeFromTheInjectedNow() {
        let twoHoursAgo = Self.now.addingTimeInterval(-2 * 60 * 60)
        #expect(MoreHubSubtitles.text(for: .dataSync, inputs(iCloudLastBackup: twoHoursAgo)) == "Bridge OK · iCloud 2 h ago")
        let halfHourAgo = Self.now.addingTimeInterval(-30 * 60)
        #expect(MoreHubSubtitles.text(for: .dataSync, inputs(iCloudLastBackup: halfHourAgo)) == "Bridge OK · iCloud just now")
        let threeDaysAgo = Self.now.addingTimeInterval(-72 * 60 * 60)
        #expect(MoreHubSubtitles.text(for: .dataSync, inputs(iCloudLastBackup: threeDaysAgo)) == "Bridge OK · iCloud 3 d ago")
    }

    @Test func dataSyncWithoutABackupShowsTheSwitch() {
        #expect(MoreHubSubtitles.text(for: .dataSync, inputs(iCloudEnabled: true)) == "Bridge OK · iCloud on")
        #expect(MoreHubSubtitles.text(for: .dataSync, inputs(bridgeConfigured: false, iCloudEnabled: false))
            == "Bridge off · iCloud off")
    }

    @Test func bridgeStatusFollowsConfiguration() {
        #expect(MoreHubSubtitles.bridgeStatus(configured: true) == "Bridge OK")
        #expect(MoreHubSubtitles.bridgeStatus(configured: false) == "Bridge off")
    }

    @Test func notificationsFollowTheMasterSwitchAndCount() {
        #expect(MoreHubSubtitles.text(for: .notifications, inputs(notificationsMasterEnabled: false)) == "Off")
        #expect(MoreHubSubtitles.text(for: .notifications, inputs(enabledReminderCount: 1)) == "1 reminder on")
        #expect(MoreHubSubtitles.text(for: .notifications, inputs(enabledReminderCount: 6)) == "6 reminders on")
    }

    @Test func aboutShowsTheVersion() {
        #expect(MoreHubSubtitles.text(for: .about, inputs()) == "1.0 (64) · based on Fud AI")
    }

    @Test func categoriesWithoutAHubSubtitleAreEmpty() {
        let covered: Set<ProfileSettingsCategory> = [.training, .foodAI, .bodyHealth, .dataSync, .notifications, .about]
        for category in ProfileSettingsCategory.allCases where !covered.contains(category) {
            #expect(MoreHubSubtitles.text(for: category, inputs()).isEmpty, "\(category.rawValue)")
        }
    }
}
