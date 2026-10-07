import Foundation

/// The plain values the More hub row subtitles read. `ProfileView` gathers them
/// from stores and settings; `MoreHubSubtitles` turns them into text.
nonisolated struct MoreHubInputs: Equatable, Sendable {
    var programName: String?
    var defaultRestLabel: String
    var foodModelName: String
    var gemmaStatus: String
    var healthKitEnabled: Bool
    var weightUnitRaw: String
    var bridgeConfigured: Bool
    var iCloudEnabled: Bool
    var iCloudLastBackupISO: String?
    var notificationsMasterEnabled: Bool
    var enabledReminderCount: Int
    var appVersion: String
    var now: Date
}

/// One home for the More hub subtitle wording.
enum MoreHubSubtitles {
    static func text(for category: ProfileSettingsCategory, _ inputs: MoreHubInputs) -> String {
        switch category {
        case .training:
            let name = inputs.programName ?? "Program V2"
            return "\(name) · rest \(inputs.defaultRestLabel)"
        case .foodAI:
            let model = inputs.foodModelName
            return "\(model) · \(inputs.gemmaStatus)"
        case .bodyHealth:
            let health = inputs.healthKitEnabled ? "Apple Health on" : "Apple Health off"
            let unit = inputs.weightUnitRaw == "kg" ? "kg" : "lb"
            return "\(health) · \(unit)"
        case .dataSync:
            let bridge = bridgeStatus(configured: inputs.bridgeConfigured)
            return "\(bridge) · \(iCloudStatus(inputs))"
        case .notifications:
            return NotificationsHubSubtitle.text(
                masterEnabled: inputs.notificationsMasterEnabled,
                reminderCount: inputs.enabledReminderCount
            )
        case .about:
            return "\(inputs.appVersion) · based on Fud AI"
        default:
            return ""
        }
    }

    static func bridgeStatus(configured: Bool) -> String {
        configured ? "Bridge OK" : "Bridge off"
    }

    private static func iCloudStatus(_ inputs: MoreHubInputs) -> String {
        guard let raw = inputs.iCloudLastBackupISO, let date = ISO8601DateFormatter().date(from: raw) else {
            return inputs.iCloudEnabled ? "iCloud on" : "iCloud off"
        }
        let hours = Int(inputs.now.timeIntervalSince(date) / 3600)
        if hours < 1 { return "iCloud just now" }
        if hours < 48 { return "iCloud \(hours) h ago" }
        return "iCloud \(hours / 24) d ago"
    }
}

enum NotificationsHubSubtitle {
    static func text(masterEnabled: Bool, reminderCount: Int) -> String {
        guard masterEnabled else { return "Off" }
        return reminderCount == 1 ? "1 reminder on" : "\(reminderCount) reminders on"
    }
}
