import SwiftUI

enum ProfileSettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case training
    case trainingAdvanced
    case foodAI
    case dailyTargets
    case mealTimes
    case waterFasting
    case homeMenu
    case shortcutsSiri
    case aiProviders
    case onDeviceModels
    case advancedAI
    case bodyHealth
    case profile
    case dataSync
    case notifications
    case about
    case acknowledgements
    case aiAccess
    case appUpdates
    case support
    case helpFeedback
    case community
    case legal

    static var preferenceCases: [Self] {
        var rows: [Self] = [.training, .foodAI, .bodyHealth, .dataSync]
        if JLFeatureFlags.fudHostedAI {
            rows.append(.aiAccess)
        }
        return rows
    }

    static var appInfoCases: [Self] {
        var rows: [Self] = [.notifications, .about]
        if JLFeatureFlags.fudUpdateCheck {
            rows.insert(.appUpdates, at: 0)
        }
        if JLFeatureFlags.fudMarketing {
            rows.append(contentsOf: [.support, .helpFeedback, .community, .legal])
        }
        return rows
    }

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .training: "Training"
        case .trainingAdvanced: "Advanced"
        case .foodAI: "Food & AI"
        case .dailyTargets: "Daily Targets"
        case .mealTimes: "Meal Times"
        case .waterFasting: "Water & Fasting"
        case .homeMenu: "Home + Menu"
        case .shortcutsSiri: "Shortcuts & Siri"
        case .aiProviders: "AI Providers"
        case .onDeviceModels: "On-Device Models"
        case .advancedAI: "Advanced AI"
        case .bodyHealth: "Body & Health"
        case .profile: "Profile"
        case .dataSync: "Data & Sync"
        case .notifications: "Notifications"
        case .about: "About"
        case .acknowledgements: "Acknowledgements"
        case .aiAccess: "AI Access"
        case .appUpdates: "App & Updates"
        case .support: "Support JL Physical"
        case .helpFeedback: "Help & Feedback"
        case .community: "Community"
        case .legal: "Legal"
        }
    }

    var systemImage: String {
        switch self {
        case .training: "figure.strengthtraining.traditional"
        case .trainingAdvanced: "wrench.and.screwdriver"
        case .foodAI: "fork.knife"
        case .dailyTargets: "target"
        case .mealTimes: "clock"
        case .waterFasting: "drop"
        case .homeMenu: "plus.circle"
        case .shortcutsSiri: "bolt.fill"
        case .aiProviders: "sparkles"
        case .onDeviceModels: "iphone.gen3"
        case .advancedAI: "slider.horizontal.3"
        case .bodyHealth: "heart"
        case .profile: "person.crop.circle"
        case .dataSync: "externaldrive"
        case .notifications: "bell"
        case .about: "info.circle"
        case .acknowledgements: "text.book.closed"
        case .aiAccess: "key.horizontal"
        case .appUpdates: "arrow.triangle.2.circlepath.circle.fill"
        case .support: "heart.fill"
        case .helpFeedback: "exclamationmark.bubble.fill"
        case .community: "person.3.fill"
        case .legal: "lock.shield.fill"
        }
    }

    var aboutCategory: AboutSettingsCategory? {
        switch self {
        case .appUpdates: .appUpdates
        case .support: .support
        case .helpFeedback: .helpFeedback
        case .community: .community
        case .legal: .legal
        default: nil
        }
    }
}
