import SwiftUI
import Photos
import PhotosUI
import PDFKit
import UIKit
import HealthKit
import StoreKit
import WidgetKit
import AVFoundation
import Speech
import UniformTypeIdentifiers
import SafariServices

// MARK: - Camera Mode
enum CameraMode {
    case snapFood
    case snapFoodWithContext
}

private let fudAIAppStoreID = "6758935726"
private let fudAIAppStoreURL = URL(string: "https://apps.apple.com/us/app/fud-ai-calorie-tracker/id6758935726")!

private enum AppUpdateState: Equatable {
    case idle
    case checking
    case upToDate(current: String, latest: String?)
    case available(current: String, latest: String, url: URL)
    case failed(current: String)

    var isUpdateAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    var hasStartedCheck: Bool {
        if case .idle = self {
            return false
        }
        return true
    }
}

private struct AppStoreLookupResponse: Decodable {
    let results: [AppStoreLookupResult]
}

private struct AppStoreLookupResult: Decodable {
    let version: String
    let trackViewUrl: String?
}

private enum AppUpdateChecker {
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    static var currentVersionDisplay: String {
        currentVersion
    }

    static func check() async -> AppUpdateState {
        let current = currentVersion

        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(fudAIAppStoreID)&country=us") else {
            return .failed(current: current)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return .failed(current: current)
            }

            let lookup = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
            guard let result = lookup.results.first else {
                return .upToDate(current: current, latest: nil)
            }

            let updateURL = result.trackViewUrl.flatMap(URL.init(string:)) ?? fudAIAppStoreURL
            if isVersion(result.version, newerThan: current) {
                return .available(current: current, latest: result.version, url: updateURL)
            }

            return .upToDate(current: current, latest: result.version)
        } catch {
            return .failed(current: current)
        }
    }

    private static func isVersion(_ latest: String, newerThan current: String) -> Bool {
        let latestParts = latest.split(separator: ".").map { Int($0) ?? 0 }
        let currentParts = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(latestParts.count, currentParts.count)

        for index in 0..<count {
            let latestValue = index < latestParts.count ? latestParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0

            if latestValue > currentValue {
                return true
            }
            if latestValue < currentValue {
                return false
            }
        }

        return false
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppThemeColor.storageKey) private var appThemeColorRaw = AppThemeColor.defaultColor.rawValue
    @State private var appUpdateState: AppUpdateState = .idle
    @State private var selectedTab: AppTab = .home
    private let routerHandoff = RouterHandoff.shared
    @State private var quickActionRequest: QuickActionRequest?
    @State private var foodLogMethodRequest: FoodLogMethodRequest?
    // One-time post-update prompts for existing users (see PostUpdatePrompts).
    @State private var showHostedUpsellPrompt = false
    @State private var showHostedUpsellPaywall = false
    @State private var showMeetDeveloperPrompt = false

    var body: some View {
        standardTabView
            .tint(AppThemeColor.color(for: appThemeColorRaw).color)
            .task {
                consumePendingLaunchRoutes()
                if JLFeatureFlags.fudUpdateCheck {
                    await refreshAppUpdateState()
                }
                if JLFeatureFlags.fudHostedAI || JLFeatureFlags.fudMarketing {
                    await runPostUpdatePromptsIfNeeded()
                }
            }
            .alert("Optional: let us handle the AI keys", isPresented: $showHostedUpsellPrompt) {
                Button("See Plus & Pro plans") {
                    showHostedUpsellPaywall = true
                }
                Button("Keep BYOK (free)", role: .cancel) {
                    continueToMeetDeveloperPrompt()
                }
            } message: {
                Text("JL Physical is free with your own API keys (BYOK) — and always will be. If juggling keys feels confusing, Plus and Pro plans run the AI for you with no keys to manage. Totally optional, nothing changes unless you switch.")
            }
            .sheet(isPresented: $showHostedUpsellPaywall, onDismiss: { continueToMeetDeveloperPrompt() }) {
                HostedPaywallView()
            }
            .sheet(isPresented: $showMeetDeveloperPrompt, onDismiss: {
                // Done marks the prompt seen before dismiss. Anything else (system
                // tear-down after opening Instagram, etc.) must bring it back.
                if PostUpdatePrompts.hasSeenMeetDeveloper {
                    scheduleProductHuntLaunchReminder()
                } else {
                    DispatchQueue.main.async {
                        showMeetDeveloperPrompt = true
                    }
                }
            }) {
                MeetDeveloperSheet {
                    PostUpdatePrompts.hasSeenMeetDeveloper = true
                    showMeetDeveloperPrompt = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .quickActionRequested)) { _ in
                consumePendingLaunchRoutes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .foodLogMethodRequested)) { _ in
                consumePendingLaunchRoutes()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    consumePendingLaunchRoutes()
                }
            }
            .onChange(of: routerHandoff.pendingFoodText) { _, text in
                if text != nil { selectedTab = .home }
            }
            .onChange(of: routerHandoff.pendingOpenTodayWorkout) { _, open in
                if open { selectedTab = .train }
            }
    }

    private var standardTabView: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                quickActionRequest: quickActionRequest,
                onQuickActionHandled: { requestID in
                    if quickActionRequest?.id == requestID { quickActionRequest = nil }
                },
                foodLogMethodRequest: foodLogMethodRequest,
                onFoodLogMethodHandled: { requestID in
                    if foodLogMethodRequest?.id == requestID { foodLogMethodRequest = nil }
                }
            )
                .tag(AppTab.home)
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }

            JLPhysicalTabView()
                .tag(AppTab.train)
                .tabItem {
                    Image(systemName: "figure.strengthtraining.traditional")
                    Text("Train")
                }
            
            ProgressTabView()
                .tag(AppTab.progress)
                .tabItem {
                    Image(systemName: "chart.bar.fill")
                    Text("Progress")
                }

            ChatView()
                .tag(AppTab.coach)
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("Coach")
                }

            ProfileView(
                updateState: $appUpdateState,
                refreshUpdateState: {
                    await refreshAppUpdateState(force: true)
                }
            )
                .tag(AppTab.settings)
                .tabItem {
                    Image(systemName: "ellipsis")
                    Text("More")
                }
                .badge(JLFeatureFlags.fudUpdateCheck && appUpdateState.isUpdateAvailable ? "!" : nil)
        }
    }

    private enum AppTab: String, Hashable {
        case home
        case train
        case progress
        case coach
        case settings
    }

    private func consumePendingLaunchRoutes() {
        if let action = QuickActionCoordinator.consumePending() {
            selectedTab = .home
            quickActionRequest = QuickActionRequest(action: action)
            return
        }
        if let method = FoodLogMethodCoordinator.consumePending() {
            selectedTab = .home
            foodLogMethodRequest = FoodLogMethodRequest(method: method)
        }
    }

    @MainActor
    private func refreshAppUpdateState(force: Bool = false) async {
        if !force && appUpdateState.hasStartedCheck {
            return
        }

        appUpdateState = .checking
        appUpdateState = await AppUpdateChecker.check()

        // A newer version is out — fire a one-shot notification (de-duped per version, gated by the
        // "App Updates" toggle) so the user finds out even if they don't scroll to the About section.
        if case let .available(_, latest, url) = appUpdateState {
            await notificationManager.notifyUpdateAvailable(version: latest, url: url)
        }
    }

    // MARK: - Post-update prompts (existing users, one-time)

    /// Sequence: hosted upsell (if eligible) → meet the developer → arm the Product Hunt
    /// launch reminder. Never stacks two dialogs; each step advances from the previous one's
    /// dismiss handler. Hosted upsell is marked seen when shown; meet-the-developer is marked
    /// seen only on Done so opening Instagram/X and coming back keeps the sheet up.
    @MainActor
    private func runPostUpdatePromptsIfNeeded() async {
        // Let the first frame and any launch route (quick action / deep link) settle first.
        try? await Task.sleep(for: .seconds(2))
        guard quickActionRequest == nil, foodLogMethodRequest == nil else {
            scheduleProductHuntLaunchReminder()
            return
        }

        if !PostUpdatePrompts.hasSeenHostedUpsell {
            // Don't treat a failed refresh as "no entitlement" — that would upsell a
            // paid BYOK subscriber and permanently consume the one-time prompt.
            let refreshed = await RevenueCatManager.shared.refreshCustomerInfo()
            guard refreshed else {
                continueToMeetDeveloperPrompt(delay: 0)
                return
            }
            if PostUpdatePrompts.isHostedUpsellEligible {
                PostUpdatePrompts.hasSeenHostedUpsell = true
                showHostedUpsellPrompt = true
                return
            }
            PostUpdatePrompts.hasSeenHostedUpsell = true
        }
        continueToMeetDeveloperPrompt(delay: 0)
    }

    private func continueToMeetDeveloperPrompt() {
        continueToMeetDeveloperPrompt(delay: 1)
    }

    private func continueToMeetDeveloperPrompt(delay: Double) {
        guard !PostUpdatePrompts.hasSeenMeetDeveloper else {
            scheduleProductHuntLaunchReminder()
            return
        }
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            showMeetDeveloperPrompt = true
        }
    }

    private func scheduleProductHuntLaunchReminder() {
        Task { await notificationManager.scheduleProductHuntLaunchReminderIfNeeded() }
    }
}

// MARK: - About (embedded as the last Settings section)
enum AboutSettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case appUpdates
    case support
    case helpFeedback
    case community
    case legal

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .appUpdates: "App & Updates"
        case .support: "Support JL Physical"
        case .helpFeedback: "Help & Feedback"
        case .community: "Community"
        case .legal: "Legal"
        }
    }

    var systemImage: String {
        switch self {
        case .appUpdates: "arrow.triangle.2.circlepath.circle.fill"
        case .support: "heart.fill"
        case .helpFeedback: "exclamationmark.bubble.fill"
        case .community: "person.3.fill"
        case .legal: "lock.shield.fill"
        }
    }
}

private struct AboutAppHeaderSection: View {
    var body: some View {
        Section {
            VStack(spacing: 8) {
                Image("onboardingLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                Text("JL Physical")
                    .font(.system(.title2, design: .rounded, weight: .bold))

                Text("Version \(AppUpdateChecker.currentVersionDisplay)")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(AppColors.appCard)
    }
}

private struct AboutFooterSection: View {
    var body: some View {
        Section {
            VStack(spacing: 4) {
                Text("Made by Apoorv Darshan")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("with care, for everyone")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }
}

private struct AboutSettingsSections: View {
    private let category: AboutSettingsCategory
    @Binding private var updateState: AppUpdateState
    private let refreshUpdateState: () async -> Void

    @State private var showShareSheet = false
    /// Open GitHub issue forms in SafariView so the GitHub app cannot swallow `?template=` and show the chooser.
    @State private var githubFormURL: URL?

    private static let bugReportURL = URL(string: "https://github.com/apoorvdarshan/fud-ai/issues/new?template=bug_report.yml")!
    private static let featureRequestURL = URL(string: "https://github.com/apoorvdarshan/fud-ai/issues/new?template=feature_request.yml")!

    init(
        category: AboutSettingsCategory,
        updateState: Binding<AppUpdateState>,
        refreshUpdateState: @escaping () async -> Void
    ) {
        self.category = category
        self._updateState = updateState
        self.refreshUpdateState = refreshUpdateState
    }

    private var shareMessage: String {
        String(localized: "I've been tracking my meals with JL Physical — snap a photo, speak it, or type it, and the AI logs the calories. It's free, open source, and your data stays on your device.\n\nDownload: https://fud-ai.app")
    }

    var body: some View {
        Group {
            switch category {
            case .appUpdates:
                Section {
                updateRow

                    Link(destination: URL(string: "https://github.com/apoorvdarshan/fud-ai")!) {
                        Label {
                            Text("Open Source (MIT)")
                        } icon: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    .tint(.primary)

                    Link(destination: URL(string: "https://www.bestpractices.dev/projects/14553")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("OpenSSF Best Practices")
                                Text("Passing · project 14553")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    .tint(.primary)

                    Link(destination: URL(string: "https://scorecard.dev/viewer/?uri=github.com/apoorvdarshan/fud-ai")!) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("OpenSSF Scorecard")
                                Text("Security health score")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "shield.checkered")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    .tint(.primary)
                }
                .listRowBackground(AppColors.appCard)

            case .support:
                Section {
                Button {
                    requestNativeReview()
                } label: {
                    Label {
                        Text("Rate the App")
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                Button {
                    showShareSheet = true
                } label: {
                    Label {
                        Text("Share the App")
                    } icon: {
                        Image(systemName: "square.and.arrow.up.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                Link(destination: URL(string: "https://github.com/apoorvdarshan/fud-ai")!) {
                    Label {
                        Text("Star on GitHub")
                    } icon: {
                        Image(systemName: "star.circle.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                Link(destination: FudAILinks.productHunt) {
                    Label {
                        Text("Vote on Product Hunt")
                    } icon: {
                        Image(systemName: "hand.thumbsup.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)
                }
                .listRowBackground(AppColors.appCard)

            case .helpFeedback:
                Section {
                Button {
                    githubFormURL = Self.bugReportURL
                } label: {
                    Label {
                        Text("Report an Issue")
                    } icon: {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                Button {
                    githubFormURL = Self.featureRequestURL
                } label: {
                    Label {
                        Text("Request a Feature")
                    } icon: {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                Link(destination: URL(string: "mailto:apoorv@fud-ai.app")!) {
                    Label {
                        Text("Contact Us")
                    } icon: {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)
                }
                .listRowBackground(AppColors.appCard)

            case .community:
                Section {
                Link(destination: FudAILinks.discord) {
                    Label {
                        Text("Join Discord")
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                Link(destination: FudAILinks.x) {
                    Label {
                        Text("Follow on X")
                    } icon: {
                        Image(systemName: "at")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                Link(destination: URL(string: "https://www.linkedin.com/company/fud-ai-app")!) {
                    Label {
                        Text("Follow on LinkedIn")
                    } icon: {
                        Image(systemName: "briefcase.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                Link(destination: FudAILinks.instagram) {
                    Label {
                        Text("Follow on Instagram")
                    } icon: {
                        Image(systemName: "camera.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)
                }
                .listRowBackground(AppColors.appCard)

            case .legal:
                Section {
                Link(destination: URL(string: "https://fud-ai.app/privacy.html")!) {
                    Label {
                        Text("Privacy Policy")
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                Link(destination: URL(string: "https://fud-ai.app/terms.html")!) {
                    Label {
                        Text("Terms of Service")
                    } icon: {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                Link(destination: URL(string: "https://udyamregistration.gov.in/")!) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Udyam Registered")
                            Text("UDYAM-DL-06-0225072 · Micro enterprise")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                Link(destination: URL(string: "https://credentials.acefitness.org/d23fcb24-899b-4588-be1b-93298a039289")!) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ACE Certified")
                            Text("Personal Trainer · NCCA-accredited")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image("ACECPTMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .tint(.primary)

                NavigationLink {
                    LiteRTLMNoticesView()
                } label: {
                    Label {
                        Text(LocalModelStrings.text(
                            "notices.legalRow",
                            defaultValue: "LiteRT-LM Third-Party Notices"
                        ))
                    } icon: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(AppColors.calorie)
                    }
                }
                .tint(.primary)

                NavigationLink {
                    WhisperBaseNoticesView()
                } label: {
                    Label("Whisper Base · MIT", systemImage: "doc.text.magnifyingglass")
                }
                .tint(.primary)
                }
                .listRowBackground(AppColors.appCard)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityShareSheet(activityItems: [shareMessage, fudAIAppStoreURL])
        }
        .sheet(isPresented: Binding(
            get: { githubFormURL != nil },
            set: { if !$0 { githubFormURL = nil } }
        )) {
            if let githubFormURL {
                SafariView(url: githubFormURL)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var updateRow: some View {
        switch updateState {
        case .checking:
            HStack {
                Label {
                    Text("Checking for Updates")
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .foregroundStyle(AppColors.calorie)
                }

                Spacer()

                ProgressView()
                    .tint(AppColors.calorie)
            }

        case .available(let current, let latest, let url):
            Button {
                UIApplication.shared.open(url)
            } label: {
                HStack(spacing: 12) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update Available")
                            Text("Current \(current) -> Latest \(latest)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(AppColors.calorie)

                            Circle()
                                .fill(AppColors.calorie)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -3)
                        }
                    }

                    Spacer()

                    Text("Update")
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.calorie)
                }
            }
            .tint(.primary)

        case .failed:
            Button {
                Task {
                    await refreshUpdateState()
                }
            } label: {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Check for Updates")
                            Text("Version \(AppUpdateChecker.currentVersionDisplay)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .foregroundStyle(AppColors.calorie)
                    }

                    Spacer()
                }
            }
            .tint(.primary)

        case .idle, .upToDate:
            Button {
                Task {
                    await refreshUpdateState()
                }
            } label: {
                HStack {
                    Label {
                        Text("App Version")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(AppColors.calorie)
                    }

                    Spacer()

                    Text(AppUpdateChecker.currentVersionDisplay)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        }
    }

    private func requestNativeReview() {
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            AppStore.requestReview(in: scene)
        }
    }
}

// MARK: - Share Sheet wrapper (UIActivityViewController)
// Used by AboutView so the personalized message AND the App Store URL
// both reach every share target. SwiftUI's ShareLink message arg is
// dropped by most targets; UIActivityViewController forwards every item.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// In-app Safari so GitHub issue form URLs keep `?template=` instead of opening the GitHub app chooser.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Nutrition Detail View
struct NutritionDetailView: View {
    let date: Date
    @Binding var homeTopNutrientsRaw: String
    @Environment(FoodStore.self) private var foodStore
    @Environment(ProfileStore.self) private var profileStore
    @Environment(WaterStore.self) private var waterStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(OptionalNutrientGoals.storageKey) private var optionalNutrientGoalsData = Data()
    @AppStorage(WaterSettings.enabledKey) private var waterTrackingEnabled = false
    @AppStorage(WaterSettings.dailyGoalKey) private var waterDailyGoal = WaterSettings.defaultDailyGoalMl
    @AppStorage(WaterSettings.unitKey) private var waterUnitRaw = WaterUnit.defaultUnit.rawValue
    @State private var showHomeNutrientPicker = false

    private var userProfile: UserProfile { profileStore.profile }
    private var optionalNutrientGoals: OptionalNutrientGoals { OptionalNutrientGoals.decoded(from: optionalNutrientGoalsData) }
    private var homeTopNutrients: [HomeTopNutrient] { HomeTopNutrient.selection(from: homeTopNutrientsRaw) }
    private var waterUnit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .defaultUnit }
    private var homeTopNutrientNames: String {
        let nutrientNames = homeTopNutrients.map(\.displayName)
        return (waterTrackingEnabled ? nutrientNames + ["Water"] : nutrientNames)
            .joined(separator: ", ")
    }

    var body: some View {
        let _ = profileStore.profile
        return NavigationStack {
            List {
                Section {
                    Button {
                        showHomeNutrientPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Label("Home Nutrient Cards", systemImage: "square.grid.3x1.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(homeTopNutrientNames)
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(AppColors.appCard)

                if waterTrackingEnabled {
                    Section {
                        NutritionDetailRow(
                            icon: "drop.fill",
                            label: "Water",
                            value: waterUnit.displayValue(forMilliliters: waterStore.total(on: date)),
                            unit: waterUnit.symbol,
                            goal: waterUnit.displayValue(forMilliliters: waterDailyGoal)
                        )
                    } header: {
                        Text("Water")
                    } footer: {
                        Text("Water is shown after your selected nutrients while Water Tracking is enabled.")
                    }
                    .listRowBackground(AppColors.appCard)
                }

                Section("Macros") {
                    NutritionDetailRow(icon: "flame.fill", label: "Calories", value: "\(foodStore.calories(for: date))", unit: "kcal", goal: "\(userProfile.effectiveCalories)")
                    NutritionDetailRow(icon: "p.circle.fill", label: "Protein", value: MacroValueFormatter.string(foodStore.protein(for: date)), unit: "g", goal: "\(userProfile.effectiveProtein)")
                    NutritionDetailRow(icon: "c.circle.fill", label: "Carbs", value: MacroValueFormatter.string(foodStore.carbs(for: date)), unit: "g", goal: "\(userProfile.effectiveCarbs)")
                    NutritionDetailRow(icon: "f.circle.fill", label: "Fat", value: MacroValueFormatter.string(foodStore.fat(for: date)), unit: "g", goal: "\(userProfile.effectiveFat)")
                }
                .listRowBackground(AppColors.appCard)

                Section("Detailed Nutrition") {
                    optionalNutritionRow(.sugar, value: foodStore.sugar(for: date))
                    optionalNutritionRow(.addedSugar, value: foodStore.addedSugar(for: date))
                    optionalNutritionRow(.fiber, value: foodStore.fiber(for: date))
                    optionalNutritionRow(.saturatedFat, value: foodStore.saturatedFat(for: date))
                    NutritionDetailRow(icon: "drop", label: "Mono Unsat. Fat", value: formatMicro(foodStore.monounsaturatedFat(for: date)), unit: "g")
                    NutritionDetailRow(icon: "drop.halffull", label: "Poly Unsat. Fat", value: formatMicro(foodStore.polyunsaturatedFat(for: date)), unit: "g")
                    optionalNutritionRow(.cholesterol, value: foodStore.cholesterol(for: date))
                    optionalNutritionRow(.caffeine, value: foodStore.caffeine(for: date))
                    optionalNutritionRow(.sodium, value: foodStore.sodium(for: date))
                    optionalNutritionRow(.potassium, value: foodStore.potassium(for: date))
                    optionalNutritionRow(.transFat, value: foodStore.transFat(for: date))
                    optionalNutritionRow(.calcium, value: foodStore.calcium(for: date))
                    optionalNutritionRow(.iron, value: foodStore.iron(for: date))
                    optionalNutritionRow(.magnesium, value: foodStore.magnesium(for: date))
                    optionalNutritionRow(.zinc, value: foodStore.zinc(for: date))
                    optionalNutritionRow(.vitaminA, value: foodStore.vitaminA(for: date))
                    optionalNutritionRow(.vitaminC, value: foodStore.vitaminC(for: date))
                    optionalNutritionRow(.vitaminD, value: foodStore.vitaminD(for: date))
                    optionalNutritionRow(.vitaminB12, value: foodStore.vitaminB12(for: date))
                    optionalNutritionRow(.vitaminE, value: foodStore.vitaminE(for: date))
                    optionalNutritionRow(.vitaminK, value: foodStore.vitaminK(for: date))
                    optionalNutritionRow(.folate, value: foodStore.folate(for: date))
                    optionalNutritionRow(.omega3, value: foodStore.omega3(for: date))
                    ForEach(SupplementalNutrient.allCases) { nutrient in
                        optionalNutritionRow(
                            nutrient.optionalNutrient,
                            value: foodStore.supplementalNutrient(nutrient, for: date)
                        )
                    }
                }
                .listRowBackground(AppColors.appCard)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.appBackground)
            .navigationTitle("Nutrition Details")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showHomeNutrientPicker) {
                HomeNutrientPickerSheet(
                    selectionRawValue: $homeTopNutrientsRaw,
                    waterTrackingEnabled: waterTrackingEnabled
                )
            }
            .onChange(of: homeTopNutrientsRaw) { _, _ in
                refreshWidgetSnapshot()
            }
            .onChange(of: optionalNutrientGoalsData) { _, _ in
                refreshWidgetSnapshot()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(AppColors.calorie)
                }
            }
        }
    }

    private func refreshWidgetSnapshot() {
        WidgetSnapshotWriter.publish(foods: foodStore.entries, profile: userProfile)
    }

    private func formatMicro(_ value: Double) -> String {
        value == 0 ? "—" : String(format: "%.1f", value)
    }

    private func optionalNutritionRow(_ nutrient: OptionalNutrient, value: Double) -> some View {
        NutritionDetailRow(
            icon: nutrient.iconName,
            label: nutrient.displayName,
            value: formatMicro(value),
            unit: nutrient.unit,
            goal: "\(optionalNutrientGoals.goal(for: nutrient))"
        )
    }
}

struct NutritionDetailRow: View {
    var icon: String? = nil
    let label: String
    let value: String
    let unit: String
    var goal: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: AppColors.calorieGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 24)
            }
            Text(LocalizedDisplayText.text(label))
                .font(.system(.body, design: .rounded))
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(AppColors.calorie)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            if let goal {
                Text("/ \(goal)")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct NativeSheetToolbarButton: View {
    let title: LocalizedStringKey
    var isEmphasized = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        button
    }

    private var button: some View {
        Button(action: action) {
            Text(title)
                .fixedSize()
                .foregroundStyle(AppColors.calorie)
        }
        .fontWeight(isEmphasized ? .semibold : .regular)
        .disabled(isDisabled)
    }
}

// MARK: - Multi-photo Capture Review
struct MultiPhotoCaptureSheet: View {
    @Binding var images: [UIImage]
    let isImportingPhotos: Bool
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    @Binding var description: String
    let onAddPhoto: () -> Void
    let onRemove: (Int) -> Void
    let onAnalyze: (Bool) -> Void
    let onCancel: () -> Void
    @State private var showAdditionalPhotoPicker = false
    @State private var progressiveMeal = false
    @State private var showProgressiveInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("\(images.count) of 10 photos")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 240, height: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            onRemove(index)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                                .frame(width: 30, height: 30)
                                                .background(.black.opacity(0.6), in: Circle())
                                        }
                                        .padding(10)
                                    }
                                    .overlay(alignment: .bottomLeading) {
                                        Text("Photo \(index + 1)")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(.black.opacity(0.55), in: Capsule())
                                            .padding(10)
                                    }
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)

                    if images.count < 10 {
                        HStack {
                            Spacer()
                            Button {
                                if isImportingPhotos {
                                    showAdditionalPhotoPicker = true
                                } else {
                                    onAddPhoto()
                                }
                            } label: {
                                Label(
                                    isImportingPhotos ? "Add Photos" : "Add Photo",
                                    systemImage: isImportingPhotos ? "photo.on.rectangle" : "camera.fill"
                                )
                            }
                            .buttonStyle(.bordered)
                            .tint(AppColors.calorie)
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Text("Progressive Meal")
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                Button {
                                    showProgressiveInfo = true
                                } label: {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundStyle(AppColors.calorie)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("How Progressive Meal works")
                            }
                            Text("Photo 1 → 2 → 3 follows each ingredient added to the same plate. Visible scale differences become ingredient weights.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Toggle("", isOn: $progressiveMeal)
                            .labelsHidden()
                            .tint(AppColors.calorie)
                            .disabled(images.count < 2)
                    }
                    .padding(14)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note for food analysis (optional)")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField(
                            "e.g. chicken is 180g, rice is 220g, use half the sauce",
                            text: $description,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Meal Photos")
            .navigationBarTitleDisplayMode(.inline)
            .photosPicker(
                isPresented: $showAdditionalPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: max(1, 10 - images.count),
                selectionBehavior: .ordered,
                matching: .images
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NativeSheetToolbarButton(title: "Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NativeSheetToolbarButton(
                        title: "Analyze",
                        isEmphasized: true,
                        isDisabled: images.isEmpty,
                        action: { onAnalyze(progressiveMeal && images.count > 1) }
                    )
                }
            }
            .onChange(of: images.count) { _, count in
                if count < 2 { progressiveMeal = false }
            }
            .alert("How Progressive Meal works", isPresented: $showProgressiveInfo) {
                Button("Done", role: .cancel) {}
            } message: {
                Text("Use this when every photo shows the same plate after another ingredient is added. Keep the photos in order and make the scale display visible. JL Physical uses the difference between consecutive scale totals to estimate each new ingredient. Leave this off when the photos are only different angles of the same meal.")
            }
        }
    }
}

// MARK: - Context Description Sheet
struct ContextDescriptionSheet: View {
    let image: UIImage?
    @Binding var description: String
    let onAnalyze: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(AppColors.calorie.opacity(0.15), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note for food analysis (optional)")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.secondary)

                        ZStack(alignment: .topLeading) {
                            if description.isEmpty {
                                Text("e.g. \"This is a half portion\" or \"Cooked in olive oil\"")
                                    .foregroundStyle(.tertiary)
                                    .font(.body)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 10)
                                    .allowsHitTesting(false)
                            }
                            TextField("", text: $description, axis: .vertical)
                                .font(.body)
                                .lineLimit(3...6)
                                .textFieldStyle(.plain)
                                .focused($isFocused)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 10)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }

                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Add Description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NativeSheetToolbarButton(title: "Cancel", action: onCancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NativeSheetToolbarButton(
                        title: "Analyze",
                        isEmphasized: true,
                        action: onAnalyze
                    )
                }
            }
            .onAppear { isFocused = true }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
}

// MARK: - Camera View (UIKit wrapper)
struct CameraView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let title: String?
    let onCancel: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(image: Binding<UIImage?>, title: String? = nil, onCancel: (() -> Void)? = nil) {
        _image = image
        self.title = title
        self.onCancel = onCancel
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.modalPresentationStyle = .fullScreen
        picker.edgesForExtendedLayout = .all
        picker.showsCameraControls = false

        // Keep the complete 4:3 camera frame visible so the preview matches the
        // original image delivered after capture. Tall screens intentionally
        // letterbox instead of enlarging and cropping the preview.
        let screenSize = UIScreen.main.bounds.size
        let previewHeight = screenSize.width * 4.0 / 3.0
        let bottomBarHeight: CGFloat = 140
        let availablePreviewHeight = max(0, screenSize.height - bottomBarHeight)
        let previewOffset = max(0, (availablePreviewHeight - previewHeight) / 2)
        picker.cameraViewTransform = CGAffineTransform(translationX: 0, y: previewOffset)

        // Custom overlay with shutter + cancel buttons
        let overlay = UIView(frame: UIScreen.main.bounds)
        overlay.isUserInteractionEnabled = true
        overlay.backgroundColor = .clear

        let bottomBar = UIView()
        bottomBar.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(bottomBar)

        let shutterOuter = UIView()
        shutterOuter.backgroundColor = .white
        shutterOuter.layer.cornerRadius = 37
        shutterOuter.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(shutterOuter)

        let shutterInner = UIView()
        shutterInner.backgroundColor = .white
        shutterInner.layer.cornerRadius = 32
        shutterInner.layer.borderWidth = 2
        shutterInner.layer.borderColor = UIColor.black.withAlphaComponent(0.15).cgColor
        shutterInner.translatesAutoresizingMaskIntoConstraints = false
        shutterOuter.addSubview(shutterInner)

        let shutterButton = UIButton(type: .system)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.addTarget(context.coordinator, action: #selector(Coordinator.capture), for: .touchUpInside)
        shutterOuter.addSubview(shutterButton)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(.white, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(context.coordinator, action: #selector(Coordinator.cancel), for: .touchUpInside)
        bottomBar.addSubview(cancelButton)

        var titleLabel: UILabel?
        if let title {
            let label = UILabel()
            label.text = title
            label.textColor = .white
            label.font = .systemFont(ofSize: 17, weight: .semibold)
            label.translatesAutoresizingMaskIntoConstraints = false
            bottomBar.addSubview(label)
            titleLabel = label
        }

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: bottomBarHeight),

            shutterOuter.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            shutterOuter.centerYAnchor.constraint(equalTo: bottomBar.topAnchor, constant: 50),
            shutterOuter.widthAnchor.constraint(equalToConstant: 74),
            shutterOuter.heightAnchor.constraint(equalToConstant: 74),

            shutterInner.centerXAnchor.constraint(equalTo: shutterOuter.centerXAnchor),
            shutterInner.centerYAnchor.constraint(equalTo: shutterOuter.centerYAnchor),
            shutterInner.widthAnchor.constraint(equalToConstant: 64),
            shutterInner.heightAnchor.constraint(equalToConstant: 64),

            shutterButton.leadingAnchor.constraint(equalTo: shutterOuter.leadingAnchor),
            shutterButton.trailingAnchor.constraint(equalTo: shutterOuter.trailingAnchor),
            shutterButton.topAnchor.constraint(equalTo: shutterOuter.topAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: shutterOuter.bottomAnchor),

            cancelButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 20),
            cancelButton.centerYAnchor.constraint(equalTo: shutterOuter.centerYAnchor),
        ])
        if let titleLabel {
            NSLayoutConstraint.activate([
                titleLabel.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
                titleLabel.topAnchor.constraint(equalTo: shutterOuter.bottomAnchor, constant: 14),
            ])
        }

        picker.cameraOverlayView = overlay
        context.coordinator.picker = picker

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        weak var picker: UIImagePickerController?

        init(_ parent: CameraView) {
            self.parent = parent
        }

        @objc func capture() {
            picker?.takePicture()
        }

        @objc func cancel() {
            parent.onCancel?()
            parent.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel?()
            parent.dismiss()
        }
    }
}

// MARK: - Barcode Scanner
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        BarcodeScannerViewController(onScan: onScan, onCancel: onCancel)
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

final class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let onScan: (String) -> Void
    private let onCancel: () -> Void
    private var session: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var captureDevice: AVCaptureDevice?
    private var didScan = false

    init(onScan: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onScan = onScan
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        buildOverlay()
        checkCameraAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = session
        DispatchQueue.global(qos: .userInitiated).async {
            session?.stopRunning()
        }
    }

    private func checkCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.showCameraUnavailable("Camera access is needed to scan barcodes.")
                    }
                }
            }
        case .denied, .restricted:
            showCameraUnavailable("Camera access is needed to scan barcodes.")
        @unknown default:
            showCameraUnavailable("Camera is unavailable.")
        }
    }

    private func configureSession() {
        let session = AVCaptureSession()
        session.beginConfiguration()

        guard let camera = BarcodeScannerCameraSelection.preferredBackVideoCaptureDevice(),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            showCameraUnavailable("Camera is unavailable.")
            return
        }
        session.addInput(input)
        captureDevice = camera
        configureCameraForBarcodeScanning(camera)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            showCameraUnavailable("Barcode scanning is unavailable.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)

        let supportedTypes: [AVMetadataObject.ObjectType] = [
            .ean13,
            .ean8,
            .upce,
            .code128,
            .code39,
            .code93,
            .itf14,
            .interleaved2of5
        ]
        let availableTypes = supportedTypes.filter { output.availableMetadataObjectTypes.contains($0) }
        guard !availableTypes.isEmpty else {
            session.commitConfiguration()
            showCameraUnavailable("Barcode scanning is unavailable.")
            return
        }
        output.metadataObjectTypes = availableTypes
        session.commitConfiguration()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)

        self.session = session
        self.previewLayer = previewLayer
        installTapToFocusGestureIfNeeded()

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func installTapToFocusGestureIfNeeded() {
        guard view.gestureRecognizers?.contains(where: { $0 is UITapGestureRecognizer }) != true else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(previewTapped(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func previewTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended,
              let previewLayer,
              let camera = captureDevice else { return }
        let layerPoint = recognizer.location(in: view)
        if view.hitTest(layerPoint, with: nil) is UIControl { return }
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
        focusCamera(camera, at: devicePoint)
    }

    private func focusCamera(_ camera: AVCaptureDevice, at devicePoint: CGPoint) {
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }

            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = devicePoint
                if camera.isFocusModeSupported(.autoFocus) {
                    camera.focusMode = .autoFocus
                } else if camera.isFocusModeSupported(.continuousAutoFocus) {
                    camera.focusMode = .continuousAutoFocus
                }
            }

            if camera.isExposurePointOfInterestSupported {
                camera.exposurePointOfInterest = devicePoint
                if camera.isExposureModeSupported(.continuousAutoExposure) {
                    camera.exposureMode = .continuousAutoExposure
                } else if camera.isExposureModeSupported(.autoExpose) {
                    camera.exposureMode = .autoExpose
                }
            }
        } catch {
            // Keep scanning available even if tap-to-focus fails.
        }
    }

    /// Food photo camera uses UIKit/system capture with autofocus. This scanner
    /// previously left the device on its default focus, which often stays soft
    /// at barcode distance on multi-camera iPhones.
    private func configureCameraForBarcodeScanning(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }

            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            } else if camera.isFocusModeSupported(.autoFocus) {
                camera.focusMode = .autoFocus
            }

            if camera.isFocusPointOfInterestSupported {
                camera.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }

            if camera.isAutoFocusRangeRestrictionSupported {
                camera.autoFocusRangeRestriction = .near
            }

            if camera.isSmoothAutoFocusSupported {
                camera.isSmoothAutoFocusEnabled = true
            }

            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }

            if camera.isExposurePointOfInterestSupported {
                camera.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }

            if camera.isLowLightBoostSupported {
                camera.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
        } catch {
            // Keep scanning available even if focus tuning fails.
        }
    }

    private func buildOverlay() {
        let closeButton = UIButton(type: .system)
        closeButton.setTitle("Cancel", for: .normal)
        closeButton.setTitleColor(.white, for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(closeButton)

        let scanBox = UIView()
        scanBox.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        scanBox.layer.borderWidth = 3
        scanBox.layer.cornerRadius = 22
        scanBox.backgroundColor = UIColor.clear
        scanBox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanBox)

        let label = UILabel()
        label.text = "Point the camera at the barcode"
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        let hint = UILabel()
        hint.text = "If the product is not found, scan the nutrition label instead."
        hint.textColor = UIColor.white.withAlphaComponent(0.72)
        hint.font = .systemFont(ofSize: 14, weight: .medium)
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 14),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            scanBox.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanBox.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -34),
            scanBox.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.76),
            scanBox.heightAnchor.constraint(equalToConstant: 190),

            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            label.topAnchor.constraint(equalTo: scanBox.bottomAnchor, constant: 28),

            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36),
            hint.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10)
        ])
    }

    private func showCameraUnavailable(_ message: String) {
        let label = UILabel()
        label.text = message
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])
    }

    @objc private func cancelTapped() {
        onCancel()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didScan,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue,
              !code.isEmpty else { return }

        didScan = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let session = session
        DispatchQueue.global(qos: .userInitiated).async {
            session?.stopRunning()
        }
        onScan(code)
    }
}

// MARK: - Food Row
struct FoodRow: View {
    let entry: FoodEntry
    @Environment(FoodStore.self) private var foodStore
    @State private var imagePreview: FullScreenImagePreview?

    private var servingText: String? {
        guard let grams = entry.servingSizeGrams else {
            let quantity = entry.reviewSelectedServingQuantity ?? 1
            let quantityText = ServingUnitEditor.formatQuantity(quantity)
            return "\(quantityText) \(String(localized: "Serving"))"
        }
        let formatted = grams == grams.rounded() ? "\(Int(grams))" : String(format: "%.1f", grams)
        if let selectedUnit = entry.selectedServingUnit,
           let quantity = entry.selectedServingQuantity,
           quantity > 0 {
            let option = ServingUnitOption.option(matching: selectedUnit, in: entry.servingUnitOptions)
            if !option.isGramUnit {
                let quantityText = ServingUnitEditor.formatQuantity(quantity)
                return "\(quantityText) \(option.displayUnit(for: quantity)) (~\(formatted)g)"
            }
        }
        return "\(formatted)g"
    }

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail — tap opens full-screen viewer without opening edit.
            if entry.imageFilename != nil || entry.imageData != nil {
                Button {
                    Task {
                        let images = await FoodEntryPhotoLoader.viewerImages(for: entry)
                        guard !images.isEmpty else { return }
                        await MainActor.run {
                            imagePreview = FullScreenImagePreview(images: images)
                        }
                    }
                } label: {
                    FoodEntryThumbnailView(
                        filename: entry.imageFilename,
                        legacyData: entry.imageData,
                        additionalCount: entry.listThumbnailAdditionalPhotoCount
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View full photo")
            } else if let emoji = entry.emoji {
                Text(emoji)
                    .font(.system(size: 28))
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: "fork.knife")
                    .font(.title3)
                    .foregroundStyle(AppColors.calorie)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    HStack(spacing: 4) {
                        Text(entry.name)
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if foodStore.isFavorite(entry) {
                            Image(systemName: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    Spacer()
                    Text(entry.timeString)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 6) {
                    Text("\(entry.calories.formatted()) kcal")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(AppColors.calorie)

                    if let serving = servingText {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(serving)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    MacroPill(label: "P", value: entry.protein)
                    MacroPill(label: "C", value: entry.carbs)
                    MacroPill(label: "F", value: entry.fat)
                }
            }
        }
        .padding(.vertical, 4)
        .fullScreenImagePreview($imagePreview)
    }
}

struct MacroPill: View {
    let label: String
    let value: Double

    var body: some View {
        Text("\(label) \(MacroValueFormatter.withUnit(value))")
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.calorie.opacity(0.08), in: Capsule())
    }
}


private struct SettingsKeyboardDismissalModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .onDisappear {
                dismissKeyboard()
            }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

enum AISettingsInfoTopic {
    case primaryAI
    case textAI
    case textFallback
    case imageFallback
    case speechToText
    case speechFallback
    case estimateCheck
    case jevRouter

    var title: String {
        switch self {
        case .primaryAI: "Primary AI"
        case .textAI: "Text AI"
        case .textFallback: "Text Fallback"
        case .imageFallback: "Image AI Fallback"
        case .speechToText: "Speech-to-Text"
        case .speechFallback: "Voice Fallback"
        case .estimateCheck: "Estimate Check"
        case .jevRouter: "Jev Router"
        }
    }

    var message: String {
        switch self {
        case .primaryAI:
            "Handles every request that includes a photo. It also handles text-only requests when Use Separate Text Provider is off. When that switch is on, Text AI handles text-only work instead."
        case .textAI:
            "An optional provider for requests without photos, including typed food, Coach chat, voice transcripts, goals, and advice. When Use Separate Text Provider is off, Primary AI handles these requests."
        case .textFallback:
            "Retries a failed text-only request once. It backs up Text AI when the separate provider is enabled; otherwise it backs up Primary AI for text-only work. It never receives photos."
        case .imageFallback:
            "Retries a failed request containing one or more photos. The first attempt always uses Primary AI. This fallback is never used for text-only requests. You may use the same provider with a different model."
        case .speechToText:
            "Converts microphone audio into text only. The transcript then follows the normal text route: Text AI when enabled, otherwise Primary AI. Matching provider API keys are reused unless you save a separate STT key."
        case .speechFallback:
            "Retries transcription when the selected remote STT provider fails. It only produces a transcript; that transcript still follows the normal text AI route. Native iOS speech already uses Apple's offline and online recognition recovery, so a separate STT fallback is available only for remote providers."
        case .estimateCheck:
            "Jev makes quick yes/no and multiple-choice decisions so the app can skip or shrink AI calls. It only receives text (never photos). Nothing is logged without your review. Estimate Check still only sends the food name, item names, and portion sizes."
        case .jevRouter:
            "The router asks Jev short questions before a bigger AI call. It is off until you turn it on, and it does nothing without a TypeSafe or AI Gateway key. Plausibility checks can flag typos on this iPhone without a key. The optional tie-break sends relative facts as text, never photos or your absolute body weight."
        }
    }
}

struct IronInfoSectionHeader: View {
    let title: String
    let infoTopic: AISettingsInfoTopic
    @State private var isShowingInfo = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .fontWidth(.condensed)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(IronTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(title)")
            Spacer(minLength: 0)
        }
        .alert(infoTopic.title, isPresented: $isShowingInfo) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text(infoTopic.message)
        }
    }
}

struct AISettingsSubsectionHeader: View {
    let title: String
    let systemImage: String
    let infoTopic: AISettingsInfoTopic

    @State private var isShowingInfo = false

    var body: some View {
        HStack(spacing: 8) {
            Label {
                subsectionTitle(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .accessibilityAddTraits(.isHeader)
            .layoutPriority(1)

            Spacer(minLength: 8)

            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(title)")
            .accessibilityHint("Shows how this provider is used")
        }
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .foregroundStyle(AppColors.calorie)
        .alert(infoTopic.title, isPresented: $isShowingInfo) {
            Button("Got it", role: .cancel) { }
        } message: {
            Text(infoTopic.message)
        }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One uppercase word per line at accessibility sizes, so "TYPESAFE" is not hyphenated.
    @ViewBuilder
    private func subsectionTitle(_ title: String) -> some View {
        let words = title.split(separator: " ").map { String($0).uppercased() }
        if dynamicTypeSize.isAccessibilitySize {
            // Capped so a long single word ("TYPESAFE") fits beside the icon and info button.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(words, id: \.self) { word in
                    Text(word)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        } else {
            Text(words.joined(separator: " "))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

struct ProfileView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(WeightStore.self) private var weightStore
    @Environment(BodyFatStore.self) private var bodyFatStore
    @Environment(FoodStore.self) private var foodStore
    @Environment(WaterStore.self) private var waterStore
    @Environment(FastingStore.self) private var fastingStore
    @Environment(StrengthWorkoutStore.self) private var strengthWorkoutStore
    @Environment(ImportedHealthWorkoutStore.self) private var importedHealthWorkoutStore
    @Environment(BodyMeasurementStore.self) private var bodyMeasurementStore
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(WeeklyChallengeStore.self) private var weeklyChallengeStore
    private var profile: UserProfile {
        get { profileStore.profile }
        nonmutating set { profileStore.profile = newValue }
    }
    private var profileBinding: Binding<UserProfile> {
        Binding(get: { profileStore.profile }, set: { profileStore.profile = $0 })
    }
    @AppStorage("heightUnit") private var heightUnitRaw = "ftin"
    @AppStorage("weightUnit") private var weightUnitRaw = "lbs"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("healthKitEnabled") private var healthKitEnabled = false
    @AppStorage(AdaptiveGoalSettings.enabledKey) private var adaptiveGoalsEnabled = true
    @AppStorage(EnergyBurnSettings.enabledKey) private var energyBurnEnabled = false
    @AppStorage("weekStartsOnMonday") private var weekStartsOnMonday = true
    @AppStorage(FoodMeasurementSettings.preferGramsByDefaultKey) private var preferGramsByDefault = false
    @AppStorage(MealPhotoSettings.saveToGalleryKey) private var saveMealPhotosToGallery = false
    @AppStorage(AppThemeColor.storageKey) private var appThemeColorRaw = AppThemeColor.defaultColor.rawValue
    @AppStorage(WaterSettings.enabledKey) private var waterTrackingEnabled = false
    @AppStorage(WaterSettings.dailyGoalKey) private var waterDailyGoal = WaterSettings.defaultDailyGoalMl
    @AppStorage(WaterSettings.unitKey) private var waterUnitRaw = WaterUnit.defaultUnit.rawValue
    @AppStorage(FastingSettings.enabledKey) private var fastingTrackingEnabled = false
    @AppStorage(FastingSettings.defaultGoalMinutesKey) private var fastingDefaultGoalMinutes = FastingSettings.defaultGoalMinutes

    private var waterUnit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .defaultUnit }

    // App-update state is owned by ContentView (it also drives the one-shot update
    // notification). It's forwarded here so the About section — now the last section
    // of Settings — can show the update row and the manual re-check.
    @Binding private var updateState: AppUpdateState
    private let refreshUpdateState: () async -> Void
    private let settingsCategory: ProfileSettingsCategory?

    init(settingsCategory: ProfileSettingsCategory? = nil) {
        self.init(
            updateState: .constant(.idle),
            refreshUpdateState: {},
            settingsCategory: settingsCategory
        )
    }

    fileprivate init(
        updateState: Binding<AppUpdateState>,
        refreshUpdateState: @escaping () async -> Void,
        settingsCategory: ProfileSettingsCategory? = nil
    ) {
        self._updateState = updateState
        self.refreshUpdateState = refreshUpdateState
        self.settingsCategory = settingsCategory
    }

    enum ActiveSheet: String, Identifiable {
        case editBirthday, editHeight, editWeight, editBodyFat, editGoalBodyFat, editGoalWeight, editCalories, editProtein, editCarbs, editFat
        var id: String { rawValue }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var showExportDiary = false
    @State private var showImportDiary = false
    @State private var showDeleteConfirmation = false
    @State private var showClearFoodLogConfirmation = false
    @State private var showCalculationMethods = false
    @State private var showWaterGoalPicker = false
    @State private var showFastingGoalPicker = false
    @State private var showAutoMacroEditAlert = false
    @State private var showMaxPinnedAlert = false
    @State private var showInvalidGoalWeightAlert = false
    @State private var showDefaultGramsInfo = false
    @State private var showAdaptiveGoalsInfo = false
    @State private var showEnergyBurnInfo = false
    @State private var energyBurnToggleReverting = false
    @State private var isRecalculatingGoals = false
    @State private var isApplyingAdaptiveGoals = false
    @State private var showAdaptiveGoalAlert = false
    @State private var adaptiveGoalAlertTitle = ""
    @State private var adaptiveGoalAlertMessage = ""
    @State private var invalidGoalWeightMessage = ""
    @State private var selectedProvider: AIProvider = AIProviderSettings.selectedProvider
    @State private var selectedModel: String = AIProviderSettings.selectedModel
    @State private var apiKeyText: String = AIProviderSettings.apiKey(for: AIProviderSettings.selectedProvider) ?? ""
    @State private var customBaseURL: String = AIProviderSettings.customBaseURL(for: AIProviderSettings.selectedProvider) ?? ""
    @AppStorage("openRouterReasoningEffort") private var openRouterReasoningEffort: OpenRouterReasoningEffort = .auto
    @State private var maxResponseTokensText: String = String(AIProviderSettings.maxResponseTokens)
    @State private var requestTimeoutSecondsText: String = String(AIProviderSettings.requestTimeoutSeconds)
    @State private var showAPIKey = false
    @State private var separateTextProviderEnabled: Bool = AIProviderSettings.separateTextProviderEnabled
    @State private var selectedTextProvider: AIProvider = AIProviderSettings.selectedTextProvider
    @State private var selectedTextModel: String = AIProviderSettings.selectedTextModel
    @State private var textApiKeyText: String = AIProviderSettings.apiKey(for: AIProviderSettings.selectedTextProvider) ?? ""
    @State private var textBaseURL: String = AIProviderSettings.customBaseURL(for: AIProviderSettings.selectedTextProvider) ?? ""
    @State private var showTextAPIKey = false
    @State private var customAIInstructions: String = AIProviderSettings.userContext
    @State private var savedAIInstructions: String = AIProviderSettings.userContext
    @FocusState private var customInstructionsFocused: Bool
    @State private var fallbackEnabled: Bool = AIProviderSettings.fallbackEnabled
    @State private var selectedFallbackProvider: AIProvider = AIProviderSettings.selectedFallbackProvider
    @State private var selectedFallbackModel: String = AIProviderSettings.selectedFallbackModel
    @State private var fallbackApiKeyText: String = AIProviderSettings.apiKey(for: AIProviderSettings.selectedFallbackProvider) ?? ""
    @State private var fallbackBaseURL: String = AIProviderSettings.fallbackCustomBaseURL(for: AIProviderSettings.selectedFallbackProvider) ?? ""
    @State private var showFallbackAPIKey = false
    @State private var textFallbackEnabled: Bool = AIProviderSettings.textFallbackEnabled
    @State private var selectedTextFallbackProvider: AIProvider = AIProviderSettings.selectedTextFallbackProvider
    @State private var selectedTextFallbackModel: String = AIProviderSettings.selectedTextFallbackModel
    @State private var textFallbackApiKeyText: String = AIProviderSettings.apiKey(for: AIProviderSettings.selectedTextFallbackProvider) ?? ""
    @State private var textFallbackBaseURL: String = AIProviderSettings.fallbackCustomBaseURL(for: AIProviderSettings.selectedTextFallbackProvider) ?? ""
    @State private var showTextFallbackAPIKey = false
    @State private var localModelAvailabilityRevision = 0
    @State private var selectedSpeechProvider: SpeechProvider = SpeechSettings.selectedProvider
    @State private var selectedSpeechLanguage: SpeechLanguage = SpeechSettings.selectedLanguage(for: SpeechSettings.selectedProvider)
    @State private var speechApiKeyText: String = SpeechSettings.apiKey(for: SpeechSettings.selectedProvider) ?? ""
    @State private var showSpeechAPIKey = false
    @State private var speechFallbackEnabled: Bool = SpeechSettings.fallbackEnabled
    @State private var selectedSpeechFallbackProvider: SpeechProvider = SpeechSettings.selectedFallbackProvider
    @State private var selectedSpeechFallbackLanguage: SpeechLanguage = SpeechSettings.selectedLanguage(for: SpeechSettings.selectedFallbackProvider)
    @State private var speechFallbackApiKeyText: String = SpeechSettings.apiKey(for: SpeechSettings.selectedFallbackProvider) ?? ""
    @State private var showSpeechFallbackAPIKey = false
    @State private var showExerciseLibrary = false
    @State private var showLegacyLogger = false
    @State private var restSoundPreview = RestTimerService()
    @State private var reconBenchStore = ReconBenchStore()
    @Environment(CloudBackupService.self) private var cloudBackup

    private var heightMetric: Bool { heightUnitRaw == "cm" }
    private var weightMetric: Bool { weightUnitRaw == "kg" }

    // Height formatting
    private var heightDisplay: String {
        if heightMetric {
            return "\(Int(profile.heightCm)) cm"
        }
        // Round to the nearest inch — truncating shows 5'6" for a 170 cm / 5'7" pick.
        let totalInches = Int((profile.heightCm / 2.54).rounded())
        let feet = totalInches / 12
        let inches = totalInches % 12
        return "\(feet)'\(inches)\""
    }

    // Weight formatting
    private var weightDisplay: String {
        if weightMetric {
            return String(format: "%.1f kg", profile.weightKg)
        }
        return String(format: "%.1f lbs", profile.weightKg * 2.20462)
    }

    // Birthday formatting
    private var birthdayDisplay: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return String(localized: "\(formatter.string(from: profile.birthday)) (age \(profile.age))")
    }

    // Goal weight display
    private var goalWeightDisplay: String {
        guard let gw = profile.goalWeightKg else { return "Not set" }
        if weightMetric {
            return String(format: "%.1f kg", gw)
        }
        return String(format: "%.1f lbs", gw * 2.20462)
    }

    /// Glanceable value for the Body Measurements row — the latest waist, or "Not set".
    private var bodyMeasurementsRowValue: String {
        guard let latest = bodyMeasurementStore.latestEntry else { return "Not set" }
        if let waist = latest.waistCm {
            return heightMetric ? String(format: "Waist %.0f cm", waist) : String(format: "Waist %.0f in", waist / 2.54)
        }
        return "Logged"
    }

    // Weekly change display
    private var weeklyChangeDisplay: String {
        let rate = profile.weeklyChangeKg ?? 0.5
        return WeightDisplayFormatter.weeklyChange(kilograms: rate, useMetric: weightMetric)
    }

    var body: some View {
        Group {
            if let settingsCategory {
                settingsList
                    .navigationTitle(Text(settingsCategory.title))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
            } else {
                NavigationStack {
                    settingsHub
                        .navigationDestination(for: ProfileSettingsCategory.self) { category in
                            switch category {
                            case .notifications:
                                NotificationSettingsView()
                            case .mealTimes:
                                MealTimeSettingsView()
                            case .homeMenu:
                                AddMenuSettingsView()
                            case .shortcutsSiri:
                                ShortcutsAndSiriSettingsView()
                            case .about:
                                AboutView()
                            case .acknowledgements:
                                AcknowledgementsView()
                            case .aiAccess:
                                if JLFeatureFlags.fudHostedAI {
                                    HostedAISettingsView()
                                }
                            default:
                                ProfileView(
                                    updateState: $updateState,
                                    refreshUpdateState: refreshUpdateState,
                                    settingsCategory: category
                                )
                            }
                        }
                }
            }
        }
    }

    private var settingsHub: some View {
        MoreHubView(inputs: hubInputs)
            .sheet(isPresented: $showExerciseLibrary) {
                WorkoutsView(presentedAsSheet: true, libraryOnly: true)
            }
            .sheet(isPresented: $showLegacyLogger) {
                WorkoutsView(presentedAsSheet: true, forcedMode: .log)
            }
    }

    private var reconHubSubtitle: String {
        let today = ReconMath.todayISO()
        let count = reconBenchStore.entries.reduce(into: 0) { partial, entry in
            partial += ReconMath.expandEntry(entry).filter { $0.date == today }.count
        }
        return count == 1 ? "1 dose today" : "\(count) doses today"
    }

    private var hubInputs: MoreHubInputs {
        MoreHubInputs(
            programName: ActiveProgramCache.load()?.name,
            defaultRestLabel: RestTimerSettings.defaultRestLabel,
            foodModelName: AIProvider.friendlyModelName(AIProviderSettings.selectedModel),
            gemmaStatus: gemmaStatusLabel,
            healthKitEnabled: healthKitEnabled,
            weightUnitRaw: weightUnitRaw,
            bridgePendingCount: WorkoutSyncService.shared.syncQueue.count,
            bridgeConfigured: !NeonBridgeSettings.load().baseURL.isEmpty,
            iCloudEnabled: cloudBackup.enabled,
            iCloudLastBackupISO: cloudBackup.lastAt,
            notificationsMasterEnabled: UserDefaults.standard.bool(forKey: "notificationsEnabled"),
            enabledReminderCount: enabledReminderCount,
            appVersion: JLAppVersion.shortAndBuild,
            now: Date()
        )
    }

    private var gemmaStatusLabel: String {
        Gemma4LocalModelManager.shared.settingsSubtitle
    }

    private var bridgeStatusLabel: String {
        MoreHubSubtitles.bridgeStatus(
            pendingCount: WorkoutSyncService.shared.syncQueue.count,
            configured: !NeonBridgeSettings.load().baseURL.isEmpty
        )
    }

    private var profileHubSubtitle: String {
        let gender = profile.gender.displayName
        return "\(gender) · \(profile.age) · \(heightDisplay)"
    }

    private var dailyTargetsSubtitle: String {
        "\(profile.effectiveCalories.formatted()) kcal · \(profile.effectiveProtein) g P"
    }

    private var waterFastingSubtitle: String {
        let water = waterTrackingEnabled ? "Water on" : "Water off"
        let fasting = fastingTrackingEnabled ? "Fasting on" : "Fasting off"
        return "\(water) · \(fasting)"
    }

    private var aiProvidersSubtitle: String {
        let model = AIProvider.friendlyModelName(AIProviderSettings.selectedModel)
        return "\(AIProviderSettings.selectedProvider.displayName) · \(model)"
    }

    private var otherNutrientsSubtitle: String {
        let count = OptionalNutrient.allCases.filter { OptionalNutrientGoals.current.goal(for: $0) > 0 }.count
        return "\(count) set"
    }

    private func autosaveCustomInstructions() {
        guard customAIInstructions != AIProviderSettings.userContext else { return }
        AIProviderSettings.userContext = customAIInstructions
        savedAIInstructions = AIProviderSettings.userContext
        customAIInstructions = savedAIInstructions
    }

    private var enabledReminderCount: Int {
        let keys: [(String, Bool)] = [
            ("breakfastReminderEnabled", true),
            ("lunchReminderEnabled", true),
            ("dinnerReminderEnabled", true),
            ("streakReminderEnabled", true),
            ("dailySummaryEnabled", true),
            ("weightLogReminderEnabled", true),
            ("bodyFatLogReminderEnabled", false),
        ]
        return keys.reduce(into: 0) { count, item in
            let on = UserDefaults.standard.object(forKey: item.0) == nil
                ? item.1
                : UserDefaults.standard.bool(forKey: item.0)
            if on { count += 1 }
        }
    }

    private var settingsList: some View {
            List {
                if settingsCategory == .training {
                    TrainingProgramSettingsSection(onExerciseLibrary: { showExerciseLibrary = true })

                    Section {
                        Stepper(value: Binding(
                            get: { RestTimerSettings.defaultSeconds },
                            set: { RestTimerSettings.defaultSeconds = $0 }
                        ), in: 15...300, step: 15) {
                            AdaptiveLabelValue {
                                UnbrokenText("Default Rest")
                            } value: {
                                UnbrokenText(RestTimerSettings.defaultRestLabel)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Toggle("10-Second Clack", isOn: Binding(
                            get: { RestTimerSettings.clackEnabled },
                            set: { RestTimerSettings.clackEnabled = $0 }
                        ))
                        Toggle("Bell at Zero", isOn: Binding(
                            get: { RestTimerSettings.bellEnabled },
                            set: { RestTimerSettings.bellEnabled = $0 }
                        ))
                        Toggle("Haptic at Zero", isOn: Binding(
                            get: { RestTimerSettings.hapticEnabled },
                            set: { RestTimerSettings.hapticEnabled = $0 }
                        ))
                        Button("Test Sounds") {
                            restSoundPreview.testSounds()
                        }
                    } header: {
                        IronSectionTitle(title: "Rest Timer")
                    } footer: {
                        Text("Cues play over your music without pausing it. Per-exercise rest still overrides Default Rest.")
                    }
                    .listRowBackground(AppColors.appCard)

                    if JLFeatureFlags.legacyWorkoutLogger {
                        NavigationLink(value: ProfileSettingsCategory.trainingAdvanced) {
                            SettingsHubRowLabel(title: "Advanced", systemImage: "wrench.and.screwdriver", subtitle: "Legacy Fud logger")
                        }
                        .listRowBackground(AppColors.appCard)
                    }
                }

                // Section 1: Personal Info
                if settingsCategory == .profile {
                Section {
                    Picker(selection: profileBinding.gender) {
                        Text("Male").tag(Gender.male)
                        Text("Female").tag(Gender.female)
                        Text("Other").tag(Gender.other)
                    } label: {
                        Label {
                            Text("Gender")
                        } icon: {
                            Image(systemName: profile.gender.icon)
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.secondary)
                    .onChange(of: profile.gender) { _, _ in saveProfile() }

                    ProfileInfoRow(icon: "birthday.cake", label: "Birthday", value: birthdayDisplay) {
                        activeSheet = .editBirthday
                    }

                    ProfileInfoRow(icon: "ruler", label: "Height", value: heightDisplay) {
                        activeSheet = .editHeight
                    }

                    ProfileInfoRow(icon: "scalemass", label: "Weight", value: weightDisplay) {
                        activeSheet = .editWeight
                    }

                    ProfileInfoRow(
                        icon: "percent",
                        label: "Body Fat",
                        value: profile.bodyFatPercentage != nil ? "\(Int(profile.bodyFatPercentage! * 100))%" : "Not set"
                    ) {
                        activeSheet = .editBodyFat
                    }

                    // Optional tape-measure circumferences. Extra signal for the AI goal calc +
                    // Coach (waist-to-hip, waist-to-height, Navy body-fat %, frame). Never edits BMR.
                    NavigationLink {
                        BodyMeasurementsDetailView(gender: profile.gender, heightCm: profile.heightCm)
                    } label: {
                        Label {
                            HStack {
                                Text("Body Measurements")
                                Spacer()
                                Text(bodyMeasurementsRowValue)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "ruler")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    let allergenSummary = profile.configuredAllergenSensitivities.joined(separator: ", ")
                    NavigationLink {
                        AllergenSensitivitiesDetailView(current: profile.configuredAllergenSensitivities) { values in
                            profile.allergenSensitivities = values
                            saveProfile()
                        }
                    } label: {
                        Label {
                            HStack {
                                Text("Allergen Sensitivities")
                                Spacer()
                                Text(allergenSummary.isEmpty ? "Not set" : allergenSummary)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                }
                .listRowBackground(AppColors.appCard)
                }

                // Section 2: Goal plan and automation. Daily nutrition targets live in a
                // separate card below so this section stays easy to scan.
                if settingsCategory == .bodyHealth {
                Section {
                    NavigationLink(value: ProfileSettingsCategory.profile) {
                        SettingsHubRowLabel(
                            title: "Profile",
                            systemImage: "person.crop.circle",
                            subtitle: profileHubSubtitle
                        )
                    }
                } header: {
                    IronSectionTitle(title: "You")
                }
                .listRowBackground(AppColors.appCard)

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weight")
                            .avoidsMidWordBreak()
                        Picker("Weight", selection: $weightUnitRaw) {
                            Text("lb").tag("lbs")
                            Text("kg").tag("kg")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .accessibilityElement(children: .contain)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Height & Length")
                            .avoidsMidWordBreak()
                        Picker("Height & Length", selection: $heightUnitRaw) {
                            Text("ft-in").tag("ftin")
                            Text("cm").tag("cm")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .accessibilityElement(children: .contain)
                    Picker(selection: $weekStartsOnMonday) {
                        Text("Sunday").tag(false)
                        Text("Monday").tag(true)
                    } label: {
                        Text("Week Starts On")
                    }
                    .pickerStyle(.menu)
                } header: {
                    IronSectionTitle(title: "Units")
                }
                .listRowBackground(AppColors.appCard)

                Section {
                    Picker(selection: profileBinding.goal) {
                        ForEach(WeightGoal.allCases, id: \.self) { goal in
                            Text(goal.displayName).tag(goal)
                        }
                    } label: {
                        Label {
                            Text("Goal")
                        } icon: {
                            Image(systemName: profile.goal.icon)
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.secondary)
                    .onChange(of: profile.goal) { _, newValue in
                        if newValue == .maintain {
                            profile.weeklyChangeKg = nil
                            profile.goalWeightKg = nil
                        } else {
                            if profile.weeklyChangeKg == nil {
                                profile.weeklyChangeKg = 0.5
                            }
                            // Clear goal weight if it no longer matches the new direction
                            // (e.g., switching from Lose to Gain with an old target below current weight).
                            if let gw = profile.goalWeightKg {
                                let losingPastTarget = newValue == WeightGoal.lose && gw >= profile.weightKg
                                let gainingPastTarget = newValue == WeightGoal.gain && gw <= profile.weightKg
                                if losingPastTarget || gainingPastTarget {
                                    profile.goalWeightKg = nil
                                }
                            }
                        }
                        saveProfile()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Picker(selection: profileBinding.activityLevel) {
                            ForEach(ActivityLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        } label: {
                            Label {
                                Text("Activity Level")
                            } icon: {
                                Image(systemName: profile.activityLevel.icon)
                                    .foregroundStyle(AppColors.calorie)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.secondary)

                        Text(profile.activityLevel.subtitle)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 34)
                    }
                    .onChange(of: profile.activityLevel) { _, _ in saveProfile() }

                    if profile.goal != .maintain {
                        Picker(selection: Binding(
                            get: { profile.weeklyChangeKg ?? 0.5 },
                            set: { profile.weeklyChangeKg = $0; saveProfile() }
                        )) {
                            Text("Slow (\(WeightDisplayFormatter.weeklyChange(kilograms: 0.25, useMetric: weightMetric, period: "wk")))").tag(0.25)
                            Text("Moderate (\(WeightDisplayFormatter.weeklyChange(kilograms: 0.5, useMetric: weightMetric, period: "wk")))").tag(0.5)
                            Text("Fast (\(WeightDisplayFormatter.weeklyChange(kilograms: 1.0, useMetric: weightMetric, period: "wk")))").tag(1.0)
                        } label: {
                            Label {
                                Text("Weekly Change")
                            } icon: {
                                Image(systemName: "gauge.with.dots.needle.33percent")
                                    .foregroundStyle(AppColors.calorie)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.secondary)

                        ProfileInfoRow(
                            icon: "flag.checkered",
                            label: "Goal Weight",
                            value: goalWeightDisplay
                        ) {
                            activeSheet = .editGoalWeight
                        }
                    }

                    if profile.bodyFatPercentage != nil {
                        ProfileInfoRow(
                            icon: "target",
                            label: "Goal Body Fat",
                            value: profile.goalBodyFatPercentage != nil ? "\(Int(profile.goalBodyFatPercentage! * 100))%" : "Not set"
                        ) {
                            activeSheet = .editGoalBodyFat
                        }
                    }
                } header: {
                    IronSectionTitle(title: "Goal")
                }
                .listRowBackground(AppColors.appCard)
                }

                if settingsCategory == .dailyTargets {
                Section {
                    lockableGoalRow(
                        icon: "flame",
                        label: "Calories",
                        valueText: "\(profile.effectiveCalories.formatted()) kcal",
                        macro: nil,
                        sheet: .editCalories
                    )

                    lockableGoalRow(icon: "p.circle", label: "Protein", valueText: "\(profile.effectiveProtein)g", macro: .protein, sheet: .editProtein)
                    lockableGoalRow(icon: "c.circle", label: "Carbs", valueText: "\(profile.effectiveCarbs)g", macro: .carbs, sheet: .editCarbs)
                    lockableGoalRow(icon: "f.circle", label: "Fat", valueText: "\(profile.effectiveFat)g", macro: .fat, sheet: .editFat)

                    NavigationLink {
                        OptionalNutrientGoalsSettingsView(profile: profile)
                    } label: {
                        Label {
                            HStack {
                                Text("Other Nutrients")
                                Spacer()
                                Text(otherNutrientsSubtitle)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "list.bullet.clipboard")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }

                    Button {
                        recalculateGoalsNow()
                    } label: {
                        Label {
                            HStack {
                                Text("Recalculate Goals")
                                Spacer()
                                if isRecalculatingGoals {
                                    ProgressView()
                                } else if goalsNeedRecalc {
                                    // Soft nudge: a goal input changed since the last recalc. A CTA
                                    // on the row's right edge, not a wrapped line below it.
                                    Text("Tap to update")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.calorie)
                                }
                            }
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    .tint(.primary)
                    .disabled(isRecalculatingGoals)

                    Button {
                        showCalculationMethods = true
                    } label: {
                        Label {
                            Text("How Targets Are Calculated")
                        } icon: {
                            Image(systemName: "book")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    .tint(.primary)
                } header: {
                    IronSectionTitle(title: "Targets")
                }
                .listRowBackground(AppColors.appCard)
                Section {
                    HStack {
                        Label {
                            Text("Adaptive Goals")
                        } icon: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(AppColors.calorie)
                        }
                        Spacer()
                        if isApplyingAdaptiveGoals {
                            ProgressView()
                        }
                        Button {
                            showAdaptiveGoalsInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("About Adaptive Goals")

                        Toggle("", isOn: $adaptiveGoalsEnabled)
                            .labelsHidden()
                            .tint(AppColors.calorie)
                            .disabled(isApplyingAdaptiveGoals)
                            .onChange(of: adaptiveGoalsEnabled) { oldValue, enabled in
                                handleAdaptiveGoalsToggle(enabled, wasEnabled: oldValue)
                            }
                    }

                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Energy Burn")
                                if !healthKitEnabled {
                                    Text("Needs Apple Health")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "flame")
                                .foregroundStyle(AppColors.calorie)
                        }
                        Spacer()
                        Button {
                            showEnergyBurnInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("About Energy Burn")

                        Toggle("", isOn: $energyBurnEnabled)
                            .labelsHidden()
                            .tint(AppColors.calorie)
                            .disabled(isRecalculatingGoals)
                            .onChange(of: energyBurnEnabled) { _, enabled in
                                handleEnergyBurnToggle(enabled)
                            }
                    }

                } header: {
                    IronSectionTitle(title: "Adaptive")
                }
                .listRowBackground(AppColors.appCard)
                }

                // Section 3: Display and input preferences. Tracking features are grouped
                // separately below so the card does not read as one long control wall.
                if settingsCategory == .foodAI {
                Section {
                    NavigationLink(value: ProfileSettingsCategory.dailyTargets) {
                        SettingsHubRowLabel(title: "Daily Targets", systemImage: "target", subtitle: dailyTargetsSubtitle)
                    }
                    if JLFeatureFlags.themeColorPicker {
                    Picker(selection: $appThemeColorRaw) {
                        ForEach(AppThemeColor.allCases) { themeColor in
                            Label {
                                Text(themeColor.displayName)
                            } icon: {
                                Image(uiImage: themeColor.menuSwatchImage)
                            }
                            .tag(themeColor.rawValue)
                        }
                    } label: {
                        Label {
                            Text("Theme Color")
                        } icon: {
                            Image(systemName: "paintpalette.fill")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.secondary)
                    }

                    AdaptiveLabelValue(alignment: .center) {
                        Label {
                            HStack(spacing: 6) {
                                Text("Default to Grams")
                                    .fixedSize(horizontal: false, vertical: true)
                                Button {
                                    showDefaultGramsInfo = true
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("About Default to Grams")
                            }
                        } icon: {
                            Image(systemName: "scalemass")
                                .foregroundStyle(AppColors.calorie)
                        }
                    } value: {
                        Toggle("Default to Grams", isOn: $preferGramsByDefault)
                            .labelsHidden()
                            .tint(AppColors.calorie)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Label {
                                Text("Save Meal Photos")
                            } icon: {
                                Image(systemName: "square.and.arrow.down")
                                    .foregroundStyle(AppColors.calorie)
                            }
                            Spacer()
                            Toggle("Save Meal Photos", isOn: $saveMealPhotosToGallery)
                                .labelsHidden()
                                .tint(AppColors.calorie)
                        }
                        Text("Also save meal photos to your gallery when logging")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 32)
                    }

                    NavigationLink(value: ProfileSettingsCategory.mealTimes) {
                        SettingsHubRowLabel(title: "Meal Times", systemImage: "clock", subtitle: "Breakfast, lunch, dinner")
                    }
                    NavigationLink(value: ProfileSettingsCategory.waterFasting) {
                        SettingsHubRowLabel(title: "Water & Fasting", systemImage: "drop", subtitle: waterFastingSubtitle)
                    }
                    NavigationLink(value: ProfileSettingsCategory.homeMenu) {
                        SettingsHubRowLabel(title: "Home + Menu", systemImage: "plus.circle", subtitle: "Home + button")
                    }
                    NavigationLink(value: ProfileSettingsCategory.shortcutsSiri) {
                        SettingsHubRowLabel(title: "Shortcuts & Siri", systemImage: "bolt.fill", subtitle: "App icon and Siri")
                    }
                } header: {
                    IronSectionTitle(title: "Food Logging")
                }
                .listRowBackground(AppColors.appCard)

                Section {
                    NavigationLink(value: ProfileSettingsCategory.aiProviders) {
                        SettingsHubRowLabel(title: "AI Providers", systemImage: "sparkles", subtitle: aiProvidersSubtitle)
                    }
                    OnDeviceModelHubRow()
                    NavigationLink(value: ProfileSettingsCategory.onDeviceModels) {
                        SettingsHubRowLabel(title: "On-Device Models", systemImage: "iphone.gen3", subtitle: gemmaStatusLabel)
                    }
                    NavigationLink(value: ProfileSettingsCategory.advancedAI) {
                        SettingsHubRowLabel(title: "Advanced AI", systemImage: "slider.horizontal.3", subtitle: "Fallbacks, timeout, instructions")
                    }
                } header: {
                    IronSectionTitle(title: "AI")
                }
                .listRowBackground(AppColors.appCard)
                }

                if settingsCategory == .waterFasting {
                Section {
                    HStack {
                        Label {
                            Text("Water Tracking")
                        } icon: {
                            Image(systemName: "drop.fill")
                                .foregroundStyle(AppColors.calorie)
                        }
                        Spacer()
                        Toggle("Water Tracking", isOn: $waterTrackingEnabled)
                            .labelsHidden()
                            .tint(AppColors.calorie)
                            .onChange(of: waterTrackingEnabled) { _, isEnabled in
                                if !isEnabled {
                                    notificationManager.scheduleWaterReminder(enabled: false, hour: 14, minute: 0)
                                    UserDefaults.standard.set(false, forKey: WaterSettings.reminderEnabledKey)
                                }
                                WidgetSnapshotWriter.publish(foods: foodStore.entries, profile: profile)
                            }
                    }

                    if waterTrackingEnabled {
                        Button {
                            showWaterGoalPicker = true
                        } label: {
                            HStack {
                                Label {
                                    Text("Daily Water Goal")
                                } icon: {
                                    Image(systemName: "target")
                                        .foregroundStyle(AppColors.calorie)
                                }
                                .foregroundStyle(.primary)
                                Spacer()
                                Text(waterUnit.formatted(milliliters: waterDailyGoal))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        Picker(selection: $waterUnitRaw) {
                            ForEach(WaterUnit.allCases) { unit in
                                Text("\(unit.title) (\(unit.symbol))").tag(unit.rawValue)
                            }
                        } label: {
                            Label {
                                Text("Water Unit")
                            } icon: {
                                Image(systemName: "ruler")
                                    .foregroundStyle(AppColors.calorie)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.secondary)
                        .onChange(of: waterUnitRaw) { _, _ in
                            WidgetSnapshotWriter.publish(foods: foodStore.entries, profile: profile)
                        }
                    }

                    HStack {
                        Label {
                            Text("Fasting Tracking")
                        } icon: {
                            Image(systemName: "timer")
                                .foregroundStyle(AppColors.calorie)
                        }
                        Spacer()
                        Toggle("Fasting Tracking", isOn: $fastingTrackingEnabled)
                            .labelsHidden()
                            .tint(AppColors.calorie)
                            .onChange(of: fastingTrackingEnabled) { _, isEnabled in
                                if !isEnabled {
                                    // Disabling tracking must never discard an in-progress
                                    // session. Complete it now so it remains in history and
                                    // no longer blocks food logging while tracking is off.
                                    _ = fastingStore.endActive()
                                    notificationManager.cancelFastingGoal()
                                }
                            }
                    }

                    if fastingTrackingEnabled {
                        Button {
                            showFastingGoalPicker = true
                        } label: {
                            HStack {
                                Label {
                                    UnbrokenText("Default Fasting Goal")
                                } icon: {
                                    Image(systemName: "target")
                                        .foregroundStyle(AppColors.calorie)
                                }
                                .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                UnbrokenText(FastingDurationFormatter.goal(minutes: fastingDefaultGoalMinutes))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                } footer: {
                    Text("Water and fasting reminders: Notifications")
                }
                .listRowBackground(AppColors.appCard)
                }

                if settingsCategory == .aiProviders || settingsCategory == .onDeviceModels {
                Section {
                    if settingsCategory == .aiProviders {
                        AISettingsSubsectionHeader(
                            title: "Photo & Text",
                            systemImage: "sparkles",
                            infoTopic: .primaryAI
                        )

                        Picker(selection: $selectedProvider) {
                            ForEach(AIProvider.visionProviders) { provider in
                                Label {
                                    Text(provider.displayName)
                                } icon: {
                                    AIProviderBrandIcon(provider: provider)
                                }
                                .tag(provider)
                            }
                        } label: {
                            Label {
                                Text("Provider")
                            } icon: {
                                AIProviderBrandIcon(provider: selectedProvider)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.secondary)
                        .id("primary-provider-\(localModelAvailabilityRevision)")
                        .onChange(of: selectedProvider) { _, newProvider in
                            AIProviderSettings.selectedProvider = newProvider
                            selectedModel = newProvider.defaultModel
                            AIProviderSettings.selectedModel = newProvider.defaultModel
                            apiKeyText = AIProviderSettings.apiKey(for: newProvider) ?? ""
                            customBaseURL = AIProviderSettings.customBaseURL(for: newProvider) ?? ""
                        }

                        AIModelPickerRow(
                            provider: selectedProvider,
                            presets: selectedProvider.models,
                            model: $selectedModel,
                            baseURL: resolvedPrimaryBaseURL,
                            apiKey: apiKeyText,
                            visionOnly: true
                        )
                        .onChange(of: selectedModel) { _, newModel in
                            AIProviderSettings.selectedModel = newModel
                        }

                        if selectedProvider.requiresAPIKey {
                            AdaptiveLabelValue {
                                Label {
                                    Text("API Key")
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                } icon: {
                                    Image(systemName: "key.fill")
                                        .foregroundStyle(AppColors.calorie)
                                }
                            } value: {
                                HStack {
                                    Group {
                                        if showAPIKey {
                                            TextField(selectedProvider.apiKeyPlaceholder, text: $apiKeyText)
                                        } else {
                                            SecureField(selectedProvider.apiKeyPlaceholder, text: $apiKeyText)
                                        }
                                    }
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onChange(of: apiKeyText) { _, newValue in
                                        let t = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        AIProviderSettings.setAPIKey(t.isEmpty ? nil : t, for: selectedProvider)
                                        ModelCatalogService.shared.scheduleRefresh(
                                            provider: selectedProvider,
                                            baseURL: resolvedPrimaryBaseURL,
                                            apiKey: t
                                        )
                                    }
                                    Button {
                                        showAPIKey.toggle()
                                    } label: {
                                        Image(systemName: showAPIKey ? "eye.fill" : "eye.slash.fill")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if selectedProvider == .ollama || selectedProvider.requiresCustomEndpoint {
                            HStack {
                                Label {
                                    Text("Server URL")
                                } icon: {
                                    Image(systemName: "link")
                                        .foregroundStyle(AppColors.calorie)
                                }
                                Spacer()
                                TextField(
                                    selectedProvider.requiresCustomEndpoint
                                        ? "https://your-endpoint.com/v1"
                                        : selectedProvider.baseURL,
                                    text: $customBaseURL
                                )
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .onChange(of: customBaseURL) { _, newValue in
                                        let t = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        AIProviderSettings.setCustomBaseURL(t.isEmpty ? nil : t, for: selectedProvider)
                                        reconcileImageFallbackModelIfDuplicate()
                                        reconcileTextFallbackModelIfDuplicate()
                                        ModelCatalogService.shared.scheduleRefresh(
                                            provider: selectedProvider,
                                            baseURL: t.isEmpty ? selectedProvider.baseURL : t,
                                            apiKey: apiKeyText
                                        )
                                    }
                            }
                        }

                        Text("Handles photos and text. Separate text AI and fallbacks: Advanced AI")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if settingsCategory == .onDeviceModels {
                        Gemma4ModelSettingsView {
                            selectedProvider = AIProviderSettings.selectedProvider
                            selectedModel = AIProviderSettings.selectedModel
                            selectedTextProvider = AIProviderSettings.selectedTextProvider
                            selectedTextModel = AIProviderSettings.selectedTextModel
                            separateTextProviderEnabled = AIProviderSettings.separateTextProviderEnabled
                            selectedFallbackProvider = AIProviderSettings.selectedFallbackProvider
                            selectedFallbackModel = AIProviderSettings.selectedFallbackModel
                            fallbackEnabled = AIProviderSettings.fallbackEnabled
                            selectedTextFallbackProvider = AIProviderSettings.selectedTextFallbackProvider
                            selectedTextFallbackModel = AIProviderSettings.selectedTextFallbackModel
                            textFallbackEnabled = AIProviderSettings.textFallbackEnabled
                            localModelAvailabilityRevision += 1
                        }
                    }

                }
                .listRowBackground(AppColors.appCard)
                }

                if settingsCategory == .aiProviders {
                Section {
                    TypeSafeEstimateCheckSection()
                } footer: {
                    TypeSafeEstimateCheckFooter()
                }
                .listRowBackground(AppColors.appCard)
                }

                if settingsCategory == .advancedAI {
                Section {
                    Toggle(isOn: $separateTextProviderEnabled) {
                        Label {
                            Text("Use Separate Text Provider")
                        } icon: {
                            Image(systemName: "text.bubble.fill")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    .tint(AppColors.calorie)
                    .onChange(of: separateTextProviderEnabled) { _, isEnabled in
                        AIProviderSettings.separateTextProviderEnabled = isEnabled
                    }

                    if separateTextProviderEnabled {
                        Picker(selection: $selectedTextProvider) {
                            ForEach(AIProvider.textProviders) { provider in
                                Label {
                                    Text(provider.displayName)
                                } icon: {
                                    AIProviderBrandIcon(provider: provider)
                                }
                                .tag(provider)
                            }
                        } label: {
                            Label {
                                Text("Provider")
                            } icon: {
                                AIProviderBrandIcon(provider: selectedTextProvider)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.secondary)
                        .id("text-provider-\(localModelAvailabilityRevision)")
                        .onChange(of: selectedTextProvider) { _, newProvider in
                            AIProviderSettings.selectedTextProvider = newProvider
                            selectedTextModel = newProvider.defaultTextModel
                            AIProviderSettings.selectedTextModel = selectedTextModel
                            textApiKeyText = AIProviderSettings.apiKey(for: newProvider) ?? ""
                            textBaseURL = AIProviderSettings.customBaseURL(for: newProvider) ?? ""
                        }

                        if selectedTextProvider == .appleIntelligence {
                            HStack {
                                Label("Model", systemImage: "brain")
                                Spacer()
                                Text(selectedTextProvider.defaultTextModel)
                                    .foregroundStyle(.secondary)
                            }

                            appleIntelligenceAvailabilityRow
                        } else {
                            AIModelPickerRow(
                                provider: selectedTextProvider,
                                presets: selectedTextProvider.textModels,
                                model: $selectedTextModel,
                                baseURL: textBaseURL.isEmpty ? selectedTextProvider.baseURL : textBaseURL,
                                apiKey: textApiKeyText,
                                visionOnly: false
                            )
                            .onChange(of: selectedTextModel) { _, newModel in
                                AIProviderSettings.selectedTextModel = newModel
                            }
                        }

                        if selectedTextProvider.requiresAPIKey && selectedTextProvider == selectedProvider {
                            LabeledContent("API Key", value: "Uses key from AI Providers")
                        } else if selectedTextProvider.requiresAPIKey {
                            HStack {
                                Label("API Key", systemImage: "key.fill")
                                Spacer()
                                Group {
                                    if showTextAPIKey {
                                        TextField(selectedTextProvider.apiKeyPlaceholder, text: $textApiKeyText)
                                    } else {
                                        SecureField(selectedTextProvider.apiKeyPlaceholder, text: $textApiKeyText)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: textApiKeyText) { _, newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    AIProviderSettings.setAPIKey(trimmed.isEmpty ? nil : trimmed, for: selectedTextProvider)
                                    ModelCatalogService.shared.scheduleRefresh(
                                        provider: selectedTextProvider,
                                        baseURL: textBaseURL.isEmpty ? selectedTextProvider.baseURL : textBaseURL,
                                        apiKey: trimmed
                                    )
                                }
                                Button {
                                    showTextAPIKey.toggle()
                                } label: {
                                    Image(systemName: showTextAPIKey ? "eye.fill" : "eye.slash.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if selectedTextProvider == .ollama || selectedTextProvider.requiresCustomEndpoint {
                            HStack {
                                Label("Server URL", systemImage: "link")
                                Spacer()
                                TextField(
                                    selectedTextProvider.requiresCustomEndpoint
                                        ? "https://your-endpoint.com/v1"
                                        : selectedTextProvider.baseURL,
                                    text: $textBaseURL
                                )
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .onChange(of: textBaseURL) { _, newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    AIProviderSettings.setCustomBaseURL(trimmed.isEmpty ? nil : trimmed, for: selectedTextProvider)
                                    reconcileTextFallbackModelIfDuplicate()
                                    ModelCatalogService.shared.scheduleRefresh(
                                        provider: selectedTextProvider,
                                        baseURL: trimmed.isEmpty ? selectedTextProvider.baseURL : trimmed,
                                        apiKey: textApiKeyText
                                    )
                                }
                            }
                        }
                    }

                } header: {
                    IronInfoSectionHeader(title: "Text AI", infoTopic: .textAI)
                }
                .listRowBackground(AppColors.appCard)

                Section {
                        Toggle(isOn: $fallbackEnabled) {
                            Label {
                                Text("Photo Fallback")
                            } icon: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(AppColors.calorie)
                            }
                        }
                        .tint(AppColors.calorie)
                        .onChange(of: fallbackEnabled) { _, newValue in
                            AIProviderSettings.fallbackEnabled = newValue
                        }

                        if fallbackEnabled {
                            // Fallback provider list shows all currently available vision providers;
                            // the same provider as primary IS allowed
                            // (so e.g. Gemini Pro primary + Gemini Flash fallback works for capacity diversity).
                            // The collision is handled at the model layer below + at the runtime check in
                            // AIProviderSettings.currentImageFallbackConfig.
                            Picker(selection: $selectedFallbackProvider) {
                                ForEach(AIProvider.visionProviders) { provider in
                                    Label {
                                        Text(provider.displayName)
                                    } icon: {
                                        AIProviderBrandIcon(provider: provider)
                                    }
                                    .tag(provider)
                                }
                            } label: {
                                Label {
                                    Text("Provider")
                                } icon: {
                                    AIProviderBrandIcon(provider: selectedFallbackProvider)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.secondary)
                            .id("image-fallback-provider-\(localModelAvailabilityRevision)")
                            .onChange(of: selectedFallbackProvider) { _, newProvider in
                                selectFallbackProvider(newProvider)
                            }

                            AIModelPickerRow(
                                provider: selectedFallbackProvider,
                                presets: selectedFallbackProvider.models,
                                model: $selectedFallbackModel,
                                baseURL: resolvedFallbackBaseURL,
                                apiKey: fallbackApiKeyText,
                                visionOnly: true,
                                excludedModelIDs: fallbackSharesPrimaryServer ? [selectedModel] : []
                            )
                            .onChange(of: selectedFallbackModel) { _, newModel in
                                AIProviderSettings.selectedFallbackModel = newModel
                            }

                            if selectedFallbackProvider.requiresAPIKey && selectedFallbackProvider == selectedProvider {
                                LabeledContent("API Key", value: "Uses key from AI Providers")
                            } else if selectedFallbackProvider.requiresAPIKey {
                                HStack {
                                    Label {
                                        Text("API Key")
                                    } icon: {
                                        Image(systemName: "key.fill")
                                            .foregroundStyle(AppColors.calorie)
                                    }
                                    Spacer()
                                    Group {
                                        if showFallbackAPIKey {
                                            TextField(selectedFallbackProvider.apiKeyPlaceholder, text: $fallbackApiKeyText)
                                        } else {
                                            SecureField(selectedFallbackProvider.apiKeyPlaceholder, text: $fallbackApiKeyText)
                                        }
                                    }
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onChange(of: fallbackApiKeyText) { _, newValue in
                                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        AIProviderSettings.setAPIKey(trimmed.isEmpty ? nil : trimmed, for: selectedFallbackProvider)
                                        ModelCatalogService.shared.scheduleRefresh(
                                            provider: selectedFallbackProvider,
                                            baseURL: resolvedFallbackBaseURL,
                                            apiKey: trimmed
                                        )
                                    }
                                    Button {
                                        showFallbackAPIKey.toggle()
                                    } label: {
                                        Image(systemName: showFallbackAPIKey ? "eye.fill" : "eye.slash.fill")
                                            .foregroundStyle(.secondary)
                                            .font(.system(size: 14))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if selectedFallbackProvider == .ollama || selectedFallbackProvider.requiresCustomEndpoint {
                                HStack {
                                    Label {
                                        Text("Server URL")
                                    } icon: {
                                        Image(systemName: "link")
                                            .foregroundStyle(AppColors.calorie)
                                    }
                                    Spacer()
                                    TextField(
                                        selectedFallbackProvider.requiresCustomEndpoint
                                            ? "https://your-endpoint.com/v1"
                                            : selectedFallbackProvider.baseURL,
                                        text: $fallbackBaseURL
                                    )
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .onChange(of: fallbackBaseURL) { _, newValue in
                                        let t = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                        AIProviderSettings.setFallbackCustomBaseURL(t.isEmpty ? nil : t, for: selectedFallbackProvider)
                                        reconcileImageFallbackModelIfDuplicate()
                                        ModelCatalogService.shared.scheduleRefresh(
                                            provider: selectedFallbackProvider,
                                            baseURL: t.isEmpty ? selectedFallbackProvider.baseURL : t,
                                            apiKey: fallbackApiKeyText
                                        )
                                    }
                                }
                            }
                        }
                } header: {
                    IronInfoSectionHeader(title: "Photo Fallback", infoTopic: .imageFallback)
                }
                .listRowBackground(AppColors.appCard)

                Section {
                        textFallbackSettingsRows
                } header: {
                    IronInfoSectionHeader(title: "Text Fallback", infoTopic: .textFallback)
                }
                .listRowBackground(AppColors.appCard)
                }

                if settingsCategory == .onDeviceModels {
                Section {
                    appleIntelligenceAvailabilityRow
                    Button("Use for text") {
                        separateTextProviderEnabled = true
                        AIProviderSettings.separateTextProviderEnabled = true
                        selectedTextProvider = .appleIntelligence
                        AIProviderSettings.selectedTextProvider = .appleIntelligence
                        selectedTextModel = AIProvider.appleIntelligence.defaultTextModel
                        AIProviderSettings.selectedTextModel = selectedTextModel
                    }
                    .disabled(!appleIntelligenceIsAvailable)
                    .opacity(appleIntelligenceIsAvailable ? 1 : 0.45)
                } header: {
                    IronSectionTitle(title: "Apple Intelligence")
                }
                .listRowBackground(AppColors.appCard)
                }

                if settingsCategory == .advancedAI {
                Section {
                    speechFallbackSettingsRows
                } header: {
                    IronInfoSectionHeader(title: "Voice Fallback", infoTopic: .speechFallback)
                }
                .listRowBackground(AppColors.appCard)

                Section {
                    AdaptiveLabelValue(alignment: .center) {
                        Label {
                            Text("Request Timeout")
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                        } icon: {
                            Image(systemName: "timer")
                                .foregroundStyle(AppColors.calorie)
                        }
                    } value: {
                        HStack(spacing: 6) {
                            requestTimeoutInput
                            Text("sec")
                                .foregroundStyle(.secondary)
                                .fixedSize()
                        }
                    }
                    AdaptiveLabelValue(alignment: .center) {
                        Label {
                            Text("Max Response Tokens")
                                .fixedSize(horizontal: false, vertical: true)
                                .layoutPriority(1)
                        } icon: {
                            Image(systemName: "text.append")
                                .foregroundStyle(AppColors.calorie)
                        }
                    } value: {
                        maxResponseTokensInput
                    }
                    if selectedProvider == .openrouter
                        || (separateTextProviderEnabled && selectedTextProvider == .openrouter)
                        || (fallbackEnabled && selectedFallbackProvider == .openrouter)
                        || (textFallbackEnabled && selectedTextFallbackProvider == .openrouter) {
                        Picker("OpenRouter Reasoning Effort", selection: $openRouterReasoningEffort) {
                            ForEach(OpenRouterReasoningEffort.allCases) { effort in
                                Text(effort.title).tag(effort)
                            }
                        }
                        Text("Applies to all OpenRouter requests. Supported levels vary by model. Higher effort may take longer and cost more. Auto keeps the model default; incomplete responses retry with Low.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    IronSectionTitle(title: "Requests")
                }
                .listRowBackground(AppColors.appCard)
                }

                if settingsCategory == .aiProviders || settingsCategory == .onDeviceModels {
                Section {
                    if settingsCategory == .aiProviders {
                        AISettingsSubsectionHeader(
                            title: "Voice Input",
                            systemImage: "waveform",
                            infoTopic: .speechToText
                        )

                        Picker(selection: $selectedSpeechProvider) {
                            ForEach(SpeechProvider.availableProviders) { provider in
                                Label {
                                    Text(provider.displayName)
                                } icon: {
                                    SpeechProviderBrandIcon(provider: provider)
                                }
                                .tag(provider)
                            }
                        } label: {
                            Label {
                                Text("Voice Provider")
                            } icon: {
                                SpeechProviderBrandIcon(provider: selectedSpeechProvider)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("settings.speech.provider")
                        .tint(.secondary)
                        .id("speech-provider-\(localModelAvailabilityRevision)")
                        .onChange(of: selectedSpeechProvider) { _, newProvider in
                            SpeechSettings.selectedProvider = newProvider
                            speechApiKeyText = SpeechSettings.apiKey(for: newProvider) ?? ""
                            selectedSpeechLanguage = SpeechSettings.selectedLanguage(for: newProvider)
                            if newProvider == selectedSpeechFallbackProvider,
                               let alternate = SpeechProvider.remoteProviders.first(where: { $0 != newProvider }) {
                                selectSpeechFallbackProvider(alternate)
                            }
                        }
                    }

                    if settingsCategory == .onDeviceModels {
                        WhisperBaseModelSettingsView(selectedProvider: $selectedSpeechProvider) {
                            selectedSpeechProvider = SpeechSettings.selectedProvider
                            selectedSpeechFallbackProvider = SpeechSettings.selectedFallbackProvider
                            speechFallbackEnabled = SpeechSettings.fallbackEnabled
                            selectedSpeechLanguage = SpeechSettings.selectedLanguage(for: selectedSpeechProvider)
                            selectedSpeechFallbackLanguage = SpeechSettings.selectedLanguage(for: selectedSpeechFallbackProvider)
                            localModelAvailabilityRevision += 1
                        }
                    }

                    if settingsCategory == .aiProviders {
                        Picker(selection: $selectedSpeechLanguage) {
                            ForEach(SpeechLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        } label: {
                            Label {
                                Text("Language")
                            } icon: {
                                Image(systemName: "globe")
                                    .foregroundStyle(AppColors.calorie)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.secondary)
                        .onChange(of: selectedSpeechLanguage) { _, newLanguage in
                            SpeechSettings.setLanguage(newLanguage, for: selectedSpeechProvider)
                        }

                        if selectedSpeechProvider.requiresAPIKey {
                            HStack {
                                Label {
                                    Text("API Key")
                                } icon: {
                                    Image(systemName: "key.fill")
                                        .foregroundStyle(AppColors.calorie)
                                }
                                Spacer()
                                Group {
                                    if showSpeechAPIKey {
                                        TextField(selectedSpeechProvider.apiKeyPlaceholder, text: $speechApiKeyText)
                                    } else {
                                        SecureField(selectedSpeechProvider.apiKeyPlaceholder, text: $speechApiKeyText)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .onChange(of: speechApiKeyText) { _, newValue in
                                    SpeechSettings.setAPIKey(newValue.isEmpty ? nil : newValue, for: selectedSpeechProvider)
                                }
                                Button {
                                    showSpeechAPIKey.toggle()
                                } label: {
                                    Image(systemName: showSpeechAPIKey ? "eye.fill" : "eye.slash.fill")
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                }
                .listRowBackground(AppColors.appCard)
                }

                // Custom AI Instructions (User Context) — prepended to every AI request when non-empty
                if settingsCategory == .advancedAI {
                Section {
                    TextField(
                        "I live in Germany, assume European portion sizes. I'm on a bodybuilding cut.",
                        text: $customAIInstructions,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .autocorrectionDisabled(false)
                    .focused($customInstructionsFocused)
                    .onSubmit { autosaveCustomInstructions() }
                    .onChange(of: customInstructionsFocused) { _, focused in
                        if !focused { autosaveCustomInstructions() }
                    }
                } header: {
                    IronSectionTitle(title: "Instructions")
                } footer: {
                    Text("Optional context sent with every AI request — region, diet, athletic goals, anything you'd otherwise repeat each time. Leave empty to disable.")
                }
                .listRowBackground(AppColors.appCard)
                .onDisappear { autosaveCustomInstructions() }
                }

                if settingsCategory == .advancedAI,
                   JevRouterSettings.visualPreview || (TypeSafeSettings.hasCredentials && (JevRouterSettings.enabled || TypeSafeSettings.enabled)) {
                Section {
                    JevRouterAdvancedSection()
                } header: {
                    IronInfoSectionHeader(title: "Jev Router", infoTopic: .jevRouter)
                }
                .listRowBackground(AppColors.appCard)
                }

                if settingsCategory == .trainingAdvanced, JLFeatureFlags.legacyWorkoutLogger {
                WorkoutLoggingSettingsSection()
                Section {
                    Button("Open Legacy Logger") { showLegacyLogger = true }
                }
                .listRowBackground(AppColors.appCard)
                }

                // Section 5: Health integration. Destructive and transfer actions are kept
                // in their own card below so they cannot be mistaken for sync preferences.
                if settingsCategory == .bodyHealth {
                Section {
                    // Apple Health
                    HStack {
                        Label {
                            Text("Apple Health")
                        } icon: {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                        }
                        Spacer()
                        Toggle("", isOn: $healthKitEnabled)
                            .labelsHidden()
                            .onChange(of: healthKitEnabled) { _, enabled in
                                handleHealthKitToggle(enabled)
                            }
                    }

                    LabeledContent("Daily Steps Goal", value: StepsGoal.current.formatted())
                    NavigationLink {
                        ProgramLibraryView()
                    } label: {
                        Text("Edit in Programs")
                            .font(.footnote)
                    }
                } header: {
                    IronSectionTitle(title: "Apple Health")
                } footer: {
                    Text("Weight and body fat from your scale (e.g. Withings) arrive through Apple Health. Steps feed the steps goal and your bridge.")
                }
                .listRowBackground(AppColors.appCard)
                }

                if settingsCategory == .dataSync {
                Section {
                    NavigationLink {
                        BridgeSettingsView()
                    } label: {
                        SettingsHubRowLabel(
                            title: "Neon Bridge",
                            systemImage: "server.rack",
                            subtitle: bridgeStatusLabel
                        )
                    }
                } header: {
                    IronSectionTitle(title: "Neon Bridge")
                }
                .listRowBackground(AppColors.appCard)

                CloudBackupSettingsSection()

                if let outcome = weeklyChallengeStore.autoDeleteOutcome {
                    WeeklyChallengeAutoDeleteSection(outcome: outcome)
                }

                Section {
                    // Export Food Diary
                    Button {
                        showExportDiary = true
                    } label: {
                        Label {
                            Text("Export Food Diary")
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        showImportDiary = true
                    } label: {
                        Label {
                            Text("Import Food Diary")
                        } icon: {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundStyle(AppColors.calorie)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    IronSectionTitle(title: "Food Diary")
                }
                .listRowBackground(AppColors.appCard)

                Section {
                    // Clear Food Log
                    Button(role: .destructive) {
                        showClearFoodLogConfirmation = true
                    } label: {
                        Label {
                            Text("Clear Food Log")
                        } icon: {
                            Image(systemName: "fork.knife")
                        }
                        .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)

                    // Delete All Data — always visible
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label {
                            Text("Delete All Data")
                        } icon: {
                            Image(systemName: "trash")
                        }
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } header: {
                    IronSectionTitle(title: "Danger Zone")
                }
                .listRowBackground(AppColors.appCard)
                }

                if let aboutCategory = settingsCategory?.aboutCategory,
                   (aboutCategory == .appUpdates && JLFeatureFlags.fudUpdateCheck)
                    || (aboutCategory != .appUpdates && JLFeatureFlags.fudMarketing) {
                    if aboutCategory == .appUpdates {
                        AboutAppHeaderSection()
                    }

                    if aboutCategory == .support {
                        TipJarSettingsSection()
                    }

                    AboutSettingsSections(
                        category: aboutCategory,
                        updateState: $updateState,
                        refreshUpdateState: refreshUpdateState
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .modifier(SettingsKeyboardDismissalModifier())
            .background(AppColors.appBackground)
            .sheet(isPresented: $showExportDiary) {
                ExportDiaryView()
            }
            .sheet(isPresented: $showImportDiary) {
                ImportDiaryView()
            }
            .sheet(isPresented: $showExerciseLibrary) {
                WorkoutsView(presentedAsSheet: true, libraryOnly: true)
            }
            .sheet(isPresented: $showLegacyLogger) {
                WorkoutsView(presentedAsSheet: true, forcedMode: .log)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .editBirthday:
                    NavigationStack {
                        VStack(spacing: 20) {
                            Text("Birthday")
                                .font(.system(.title2, design: .rounded, weight: .bold))

                            DatePicker(
                                "Birthday",
                                selection: profileBinding.birthday,
                                in: ...Date.now,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()

                            Button {
                                saveProfile()
                                activeSheet = nil
                            } label: {
                                Text("Save")
                                    .font(.system(.headline, design: .rounded, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        LinearGradient(colors: AppColors.calorieGradient, startPoint: .leading, endPoint: .trailing)
                                    )
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .padding(.horizontal, 24)

                            Spacer()
                        }
                        .padding(.top, 24)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { activeSheet = nil }
                            }
                        }
                    }
                    .presentationDetents([.medium])

                case .editHeight:
                    HeightPickerSheet(
                        currentHeightCm: profile.heightCm
                    ) { newHeight in
                        profile.heightCm = newHeight
                        saveProfile()
                    }

                case .editWeight:
                    WeightPickerSheet(
                        currentWeightKg: profile.weightKg,
                        previous: weightStore.latestEntry
                    ) { newWeight in
                        profile.weightKg = newWeight
                        // Invalidate goal weight if the new current weight makes the direction impossible.
                        if let gw = profile.goalWeightKg {
                            let mismatch = (profile.goal == .lose && gw >= newWeight)
                                        || (profile.goal == .gain && gw <= newWeight)
                            if mismatch { profile.goalWeightKg = nil }
                        }
                        saveProfile()
                        weightStore.addEntry(WeightEntry(weightKg: newWeight))
                    }

                case .editBodyFat:
                    BodyFatPickerSheet(
                        currentPercentage: profile.bodyFatPercentage
                    ) { newValue in
                        profile.bodyFatPercentage = newValue
                        // Goal body fat only makes sense alongside a current
                        // value — clear it whenever the current is cleared so
                        // a stale goal doesn't linger on a user who's opted out.
                        if newValue == nil { profile.goalBodyFatPercentage = nil }
                        saveProfile()
                    }

                case .editGoalBodyFat:
                    // Goal body fat is purely cosmetic — does NOT participate
                    // in BMR / TDEE / macro math, so editing it just saves.
                    GoalBodyFatPickerSheet(
                        currentGoal: profile.goalBodyFatPercentage,
                        currentBodyFat: profile.bodyFatPercentage
                    ) { newValue in
                        profile.goalBodyFatPercentage = newValue
                        saveProfile()
                    }

                case .editGoalWeight:
                    WeightPickerSheet(
                        currentWeightKg: profile.goalWeightKg ?? profile.weightKg
                    ) { newGoalWeight in
                        // Validate against current goal direction.
                        let invalid = (profile.goal == .lose && newGoalWeight >= profile.weightKg)
                                   || (profile.goal == .gain && newGoalWeight <= profile.weightKg)
                        if invalid {
                            invalidGoalWeightMessage = profile.goal == .lose
                                ? "A Lose goal needs a target below your current weight."
                                : "A Gain goal needs a target above your current weight."
                            showInvalidGoalWeightAlert = true
                            return
                        }
                        profile.goalWeightKg = newGoalWeight
                        saveProfile()
                    }

                case .editCalories:
                    NutritionPickerSheet(
                        label: "Calories", unit: "kcal",
                        currentValue: profile.effectiveCalories,
                        range: 800...6000, step: 50,
                        onSave: { setCalories(to: $0) },
                        onResetToAuto: profile.isCaloriesLocked ? { resetCaloriesLock() } : nil
                    )

                case .editProtein:
                    NutritionPickerSheet(
                        label: "Protein", unit: "g",
                        currentValue: profile.effectiveProtein,
                        range: 10...500, step: 5,
                        onSave: { setMacro(.protein, to: $0) },
                        onResetToAuto: profile.isMacroLocked(.protein) ? { resetMacroLock(.protein) } : nil
                    )

                case .editCarbs:
                    NutritionPickerSheet(
                        label: "Carbs", unit: "g",
                        currentValue: profile.effectiveCarbs,
                        range: 0...800, step: 5,
                        onSave: { setMacro(.carbs, to: $0) },
                        onResetToAuto: profile.isMacroLocked(.carbs) ? { resetMacroLock(.carbs) } : nil
                    )

                case .editFat:
                    NutritionPickerSheet(
                        label: "Fat", unit: "g",
                        currentValue: profile.effectiveFat,
                        range: 10...300, step: 5,
                        onSave: { setMacro(.fat, to: $0) },
                        onResetToAuto: profile.isMacroLocked(.fat) ? { resetMacroLock(.fat) } : nil
                    )

                }
            }
            .settingsFloatingTabClearance()
            .alert("Clear Food Log", isPresented: $showClearFoodLogConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All Logs", role: .destructive) {
                    foodStore.replaceAllEntries([])
                }
            } message: {
                Text("This will permanently delete all your logged food entries. Your profile, weight entries, favorites, and workout history will be kept. This action cannot be undone.")
            }
            .alert("Default to Grams", isPresented: $showDefaultGramsInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("When enabled, new food results open with grams selected even if the AI detects cups, portions, or servings. You can still switch units for each food.")
            }
            .alert("Adaptive Goals", isPresented: $showAdaptiveGoalsInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("About once a week when you open the app, JL Physical automatically re-runs the full goal calculation — the same one the Recalculate button uses — from your profile, recent logged food, and weight trend. If Energy Burn is on, it uses your measured burn as the maintenance anchor. It skips silently if the AI is unavailable. Turning this off restores the targets from before Adaptive Goals first changed them. This is not medical advice.")
            }
            .alert("Energy Burn", isPresented: $showEnergyBurnInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("When on, JL Physical uses Apple Health’s recent measured-energy window as your maintenance anchor when calculating goals instead of the formula estimate: measured total energy when enough days are available; otherwise, average measured active energy + formula BMR. No AI is used to read your burn. Requires Apple Health. Works with the Recalculate button and with Adaptive Goals.")
            }
            .alert(adaptiveGoalAlertTitle, isPresented: $showAdaptiveGoalAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(adaptiveGoalAlertMessage)
            }
            .sheet(isPresented: $showCalculationMethods) {
                CalculationMethodsView()
            }
            .sheet(isPresented: $showWaterGoalPicker) {
                WaterGoalPickerSheet(currentGoal: waterDailyGoal, unit: waterUnit) {
                    waterDailyGoal = $0
                    WidgetSnapshotWriter.publish(foods: foodStore.entries, profile: profile)
                }
            }
            .sheet(isPresented: $showFastingGoalPicker) {
                FastingGoalPickerSheet(currentGoalMinutes: fastingDefaultGoalMinutes) {
                    fastingDefaultGoalMinutes = $0
                }
            }
            .onAppear {
                // Existing users (and anyone who has never recalculated) start with no baseline.
                // Seed it to the current inputs so the "recalculate suggested" nudge only appears
                // after a genuine change from here on, instead of firing on first launch.
                if UserDefaults.standard.string(forKey: Self.lastRecalcGoalSignatureKey) == nil {
                    markGoalsRecalculated()
                }
            }
            .alert("Can't Rebalance", isPresented: $showAutoMacroEditAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Calories is locked and both other macros are locked, so there's nothing left to absorb this change. Unlock calories or another macro, then try again.")
            }
            .alert("Max 2 Macros Locked", isPresented: $showMaxPinnedAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("At most 2 macros can be locked at a time, so one stays free to balance. Unlock another macro first (tap its lock icon).")
            }
            .alert("Invalid Goal Weight", isPresented: $showInvalidGoalWeightAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(invalidGoalWeightMessage)
            }
            .alert("Delete All Data", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Everything", role: .destructive) {
                    Task {
                        // Try the server first. On failure, only the deletion marker
                        // and bearer survive in Keychain so deletion can retry later.
                        await weeklyChallengeStore.deleteRemoteProfileForFullReset()

                        // Apple Health samples remain untouched; users manage those
                        // from the Health app's Sources > JL Physical screen.
                        foodStore.replaceAllEntries([])
                        weightStore.replaceAllEntries([])
                        waterStore.clear()
                        fastingStore.clear()
                        strengthWorkoutStore.clearAll()
                        importedHealthWorkoutStore.clearAll()
                        FoodImageStore.shared.deleteAll()
                        notificationManager.cancelAllNotifications()
                        let domain = Bundle.main.bundleIdentifier ?? ""
                        UserDefaults.standard.removePersistentDomain(forName: domain)
                        AIProviderSettings.deleteAllData()
                        SpeechSettings.deleteAllData()
                        TypeSafeSettings.deleteAllData()
                        JevRouterSettings.deleteAllData()
                        OnDeviceModelSettings.deleteAllData()
                        chatStore.reset()
                        WidgetSnapshot.clear()
                        WidgetCenter.shared.reloadAllTimelines()
                        hasCompletedOnboarding = false
                    }
                }
            } message: {
                Text("This will permanently delete all your data including food logs, weight entries, workout history, and profile. This action cannot be undone.")
            }
    }
    private var requestTimeoutInput: some View {
        EndEditingDecimalTextField(
            text: $requestTimeoutSecondsText,
            focusRequest: 0,
            onEditingChanged: { _ in },
            keyboardType: .numberPad,
            placeholder: "180",
            accessibilityLabel: "Request Timeout"
        )
            .frame(width: 70)
            .onChange(of: requestTimeoutSecondsText) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                if digits != newValue { requestTimeoutSecondsText = digits }
                if let seconds = Int(digits), seconds > 0 {
                    AIProviderSettings.requestTimeoutSeconds = seconds
                }
            }
    }

    @ViewBuilder
    private var textFallbackSettingsRows: some View {
        Toggle(isOn: $textFallbackEnabled) {
            Label("Text Fallback", systemImage: "arrow.triangle.2.circlepath")
        }
        .tint(AppColors.calorie)
        .onChange(of: textFallbackEnabled) { _, newValue in
            AIProviderSettings.textFallbackEnabled = newValue
        }

        if textFallbackEnabled {
            Picker(selection: $selectedTextFallbackProvider) {
                ForEach(AIProvider.textProviders) { provider in
                    Label {
                        Text(provider.displayName)
                    } icon: {
                        AIProviderBrandIcon(provider: provider)
                    }
                    .tag(provider)
                }
            } label: {
                Label {
                    Text("Provider")
                } icon: {
                    AIProviderBrandIcon(provider: selectedTextFallbackProvider)
                }
            }
            .pickerStyle(.menu)
            .tint(.secondary)
            .id("text-fallback-provider-\(localModelAvailabilityRevision)")
            .onChange(of: selectedTextFallbackProvider) { _, newProvider in
                selectTextFallbackProvider(newProvider)
            }

            if selectedTextFallbackProvider == .appleIntelligence {
                HStack {
                    Label("Model", systemImage: "brain")
                    Spacer()
                    Text(selectedTextFallbackProvider.defaultTextModel)
                        .foregroundStyle(.secondary)
                }
                appleIntelligenceAvailabilityRow
            } else {
                AIModelPickerRow(
                    provider: selectedTextFallbackProvider,
                    presets: selectedTextFallbackProvider.textModels,
                    model: $selectedTextFallbackModel,
                    baseURL: resolvedTextFallbackBaseURL,
                    apiKey: textFallbackApiKeyText,
                    visionOnly: false,
                    excludedModelIDs: textFallbackSharesPrimaryServer ? [separateTextProviderEnabled ? selectedTextModel : selectedModel] : []
                )
                .onChange(of: selectedTextFallbackModel) { _, newModel in
                    AIProviderSettings.selectedTextFallbackModel = newModel
                }
            }

            if selectedTextFallbackProvider.requiresAPIKey && selectedTextFallbackProvider == selectedProvider {
                LabeledContent("API Key", value: "Uses key from AI Providers")
            } else if selectedTextFallbackProvider.requiresAPIKey {
                HStack {
                    Label("API Key", systemImage: "key.fill")
                    Spacer()
                    Group {
                        if showTextFallbackAPIKey {
                            TextField(selectedTextFallbackProvider.apiKeyPlaceholder, text: $textFallbackApiKeyText)
                        } else {
                            SecureField(selectedTextFallbackProvider.apiKeyPlaceholder, text: $textFallbackApiKeyText)
                        }
                    }
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: textFallbackApiKeyText) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        AIProviderSettings.setAPIKey(trimmed.isEmpty ? nil : trimmed, for: selectedTextFallbackProvider)
                        ModelCatalogService.shared.scheduleRefresh(
                            provider: selectedTextFallbackProvider,
                            baseURL: resolvedTextFallbackBaseURL,
                            apiKey: trimmed
                        )
                    }
                    Button {
                        showTextFallbackAPIKey.toggle()
                    } label: {
                        Image(systemName: showTextFallbackAPIKey ? "eye.fill" : "eye.slash.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedTextFallbackProvider == .ollama || selectedTextFallbackProvider.requiresCustomEndpoint {
                HStack {
                    Label("Server URL", systemImage: "link")
                    Spacer()
                    TextField(
                        selectedTextFallbackProvider.requiresCustomEndpoint
                            ? "https://your-endpoint.com/v1"
                            : selectedTextFallbackProvider.baseURL,
                        text: $textFallbackBaseURL
                    )
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .onChange(of: textFallbackBaseURL) { _, newValue in
                        let t = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        AIProviderSettings.setFallbackCustomBaseURL(t.isEmpty ? nil : t, for: selectedTextFallbackProvider)
                        reconcileTextFallbackModelIfDuplicate()
                        ModelCatalogService.shared.scheduleRefresh(
                            provider: selectedTextFallbackProvider,
                            baseURL: t.isEmpty ? selectedTextFallbackProvider.baseURL : t,
                            apiKey: textFallbackApiKeyText
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var speechFallbackSettingsRows: some View {
        if selectedSpeechProvider == .nativeIOS || speechFallbackProviderOptions.isEmpty {
            Text("Native iOS speech already recovers on this iPhone, so there is no separate voice fallback.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if selectedSpeechProvider != .nativeIOS {
            Toggle(isOn: $speechFallbackEnabled) {
                Label("Voice Fallback", systemImage: "arrow.triangle.2.circlepath")
            }
            .tint(AppColors.calorie)
            .onChange(of: speechFallbackEnabled) { _, newValue in
                SpeechSettings.fallbackEnabled = newValue
                if newValue, selectedSpeechFallbackProvider == selectedSpeechProvider,
                   let alternate = speechFallbackProviderOptions.first {
                    selectSpeechFallbackProvider(alternate)
                }
            }

            if speechFallbackEnabled {
                Picker(selection: $selectedSpeechFallbackProvider) {
                    ForEach(speechFallbackProviderOptions) { provider in
                        Label {
                            Text(provider.displayName)
                        } icon: {
                            SpeechProviderBrandIcon(provider: provider)
                        }
                        .tag(provider)
                    }
                } label: {
                    Label {
                        Text("Provider")
                    } icon: {
                        SpeechProviderBrandIcon(provider: selectedSpeechFallbackProvider)
                    }
                }
                .pickerStyle(.menu)
                .tint(.secondary)
                .id("speech-fallback-provider-\(localModelAvailabilityRevision)")
                .onAppear {
                    if !speechFallbackProviderOptions.contains(selectedSpeechFallbackProvider),
                       let alternate = speechFallbackProviderOptions.first {
                        selectSpeechFallbackProvider(alternate)
                    }
                }
                .onChange(of: selectedSpeechFallbackProvider) { _, newProvider in
                    selectSpeechFallbackProvider(newProvider)
                }

                Picker(selection: $selectedSpeechFallbackLanguage) {
                    ForEach(SpeechLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                } label: {
                    Label("Language", systemImage: "globe")
                }
                .pickerStyle(.menu)
                .tint(.secondary)
                .onChange(of: selectedSpeechFallbackLanguage) { _, newLanguage in
                    SpeechSettings.setLanguage(newLanguage, for: selectedSpeechFallbackProvider)
                }

                if selectedSpeechFallbackProvider.requiresAPIKey {
                    HStack {
                        Label("API Key", systemImage: "key.fill")
                        Spacer()
                        Group {
                            if showSpeechFallbackAPIKey {
                                TextField(selectedSpeechFallbackProvider.apiKeyPlaceholder, text: $speechFallbackApiKeyText)
                            } else {
                                SecureField(selectedSpeechFallbackProvider.apiKeyPlaceholder, text: $speechFallbackApiKeyText)
                            }
                        }
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: speechFallbackApiKeyText) { _, newValue in
                            SpeechSettings.setAPIKey(newValue.isEmpty ? nil : newValue, for: selectedSpeechFallbackProvider)
                        }
                        Button {
                            showSpeechFallbackAPIKey.toggle()
                        } label: {
                            Image(systemName: showSpeechFallbackAPIKey ? "eye.fill" : "eye.slash.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var appleIntelligenceIsAvailable: Bool {
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            return OnDeviceAIService.isAvailable
            #else
            return false
            #endif
        }
        return false
    }

    @ViewBuilder
    private var appleIntelligenceAvailabilityRow: some View {
        if #available(iOS 26.0, *) {
            #if canImport(FoundationModels)
            let available = OnDeviceAIService.isAvailable
            Label {
                Text(OnDeviceAIService.availabilityDescription)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(available ? Color.green : Color.orange)
            }
            #else
            Label("Apple Intelligence is unavailable in this build", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
            #endif
        } else {
            Label("Requires iOS 26 or later", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var maxResponseTokensInput: some View {
        EndEditingDecimalTextField(
            text: $maxResponseTokensText,
            focusRequest: 0,
            onEditingChanged: { _ in },
            keyboardType: .numberPad,
            placeholder: "1024",
            accessibilityLabel: "Max Response Tokens"
        )
            .frame(width: 90)
            .onChange(of: maxResponseTokensText) { _, newValue in
                let digits = newValue.filter(\.isNumber)
                if digits != newValue { maxResponseTokensText = digits }
                if let tokens = Int(digits), tokens > 0 {
                    AIProviderSettings.maxResponseTokens = tokens
                }
            }
    }

    private var resolvedPrimaryBaseURL: String {
        let trimmed = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? selectedProvider.baseURL : trimmed
    }

    private var resolvedFallbackBaseURL: String {
        let trimmed = fallbackBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? selectedFallbackProvider.baseURL : trimmed
    }

    /// True when fallback would hit the same provider, model, and server as primary.
    private var fallbackSharesPrimaryServer: Bool {
        selectedFallbackProvider == selectedProvider && resolvedPrimaryBaseURL == resolvedFallbackBaseURL
    }

    private var resolvedTextPrimaryBaseURL: String {
        let provider = separateTextProviderEnabled ? selectedTextProvider : selectedProvider
        let url = separateTextProviderEnabled ? textBaseURL : customBaseURL
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.baseURL : trimmed
    }

    private var resolvedTextFallbackBaseURL: String {
        let trimmed = textFallbackBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? selectedTextFallbackProvider.baseURL : trimmed
    }

    private var textFallbackSharesPrimaryServer: Bool {
        let primaryProvider = separateTextProviderEnabled ? selectedTextProvider : selectedProvider
        return selectedTextFallbackProvider == primaryProvider &&
            resolvedTextPrimaryBaseURL == resolvedTextFallbackBaseURL
    }

    private var speechFallbackProviderOptions: [SpeechProvider] {
        SpeechProvider.availableBatchProviders.filter { $0 != selectedSpeechProvider }
    }

    private func saveProfile() {
        profile.save()
    }

    private func selectFallbackProvider(_ newProvider: AIProvider) {
        AIProviderSettings.selectedFallbackProvider = newProvider
        if !newProvider.models.contains(selectedFallbackModel) {
            selectedFallbackModel = newProvider.defaultModel
            AIProviderSettings.selectedFallbackModel = selectedFallbackModel
        }
        // Same provider + same server + same model would be a pointless retry — pick an alternate.
        let sharesServer = newProvider == selectedProvider &&
            (AIProviderSettings.fallbackCustomBaseURL(for: newProvider) ?? newProvider.baseURL) ==
            (AIProviderSettings.customBaseURL(for: selectedProvider) ?? selectedProvider.baseURL)
        if sharesServer,
           selectedFallbackModel == selectedModel,
           let alternateModel = newProvider.models.first(where: { $0 != selectedModel }) {
            selectedFallbackModel = alternateModel
            AIProviderSettings.selectedFallbackModel = alternateModel
        }
        fallbackApiKeyText = AIProviderSettings.apiKey(for: newProvider) ?? ""
        fallbackBaseURL = AIProviderSettings.fallbackCustomBaseURL(for: newProvider) ?? ""
    }

    private func selectTextFallbackProvider(_ newProvider: AIProvider) {
        AIProviderSettings.selectedTextFallbackProvider = newProvider
        let options = newProvider.textModels
        if !options.contains(selectedTextFallbackModel) {
            selectedTextFallbackModel = newProvider.defaultTextModel
            AIProviderSettings.selectedTextFallbackModel = selectedTextFallbackModel
        }
        let primaryProvider = separateTextProviderEnabled ? selectedTextProvider : selectedProvider
        let primaryModel = separateTextProviderEnabled ? selectedTextModel : selectedModel
        let sharesServer = newProvider == primaryProvider &&
            (AIProviderSettings.fallbackCustomBaseURL(for: newProvider) ?? newProvider.baseURL) ==
            (AIProviderSettings.customBaseURL(for: primaryProvider) ?? primaryProvider.baseURL)
        if sharesServer,
           selectedTextFallbackModel == primaryModel,
           let alternate = options.first(where: { $0 != primaryModel }) {
            selectedTextFallbackModel = alternate
            AIProviderSettings.selectedTextFallbackModel = alternate
        }
        textFallbackApiKeyText = AIProviderSettings.apiKey(for: newProvider) ?? ""
        textFallbackBaseURL = AIProviderSettings.fallbackCustomBaseURL(for: newProvider) ?? ""
    }

    private func reconcileImageFallbackModelIfDuplicate() {
        guard fallbackEnabled else { return }
        guard selectedFallbackProvider == selectedProvider,
              selectedFallbackModel == selectedModel,
              resolvedPrimaryBaseURL == resolvedFallbackBaseURL else { return }
        guard let alternate = selectedFallbackProvider.models.first(where: { $0 != selectedModel }) else { return }
        selectedFallbackModel = alternate
        AIProviderSettings.selectedFallbackModel = alternate
    }

    private func reconcileTextFallbackModelIfDuplicate() {
        guard textFallbackEnabled else { return }
        let primaryProvider = separateTextProviderEnabled ? selectedTextProvider : selectedProvider
        let primaryModel = separateTextProviderEnabled ? selectedTextModel : selectedModel
        guard selectedTextFallbackProvider == primaryProvider,
              selectedTextFallbackModel == primaryModel,
              resolvedTextPrimaryBaseURL == resolvedTextFallbackBaseURL else { return }
        guard let alternate = selectedTextFallbackProvider.textModels.first(where: { $0 != primaryModel }) else { return }
        selectedTextFallbackModel = alternate
        AIProviderSettings.selectedTextFallbackModel = alternate
    }

    private func selectSpeechFallbackProvider(_ newProvider: SpeechProvider) {
        SpeechSettings.selectedFallbackProvider = newProvider
        selectedSpeechFallbackLanguage = SpeechSettings.selectedLanguage(for: newProvider)
        speechFallbackApiKeyText = SpeechSettings.apiKey(for: newProvider) ?? ""
    }

    private static let lastRecalcGoalSignatureKey = "lastRecalcGoalSignature"

    /// True when a goal-relevant input (weight, activity, goal, pace, …) has changed since the
    /// last Recalculate. Recalculate stays tappable at all times — this only drives a soft
    /// "your profile changed, recalculate to refresh" nudge, never disables the button.
    private var goalsNeedRecalc: Bool {
        guard let stored = UserDefaults.standard.string(forKey: Self.lastRecalcGoalSignatureKey) else { return false }
        return stored != profile.goalInputSignature
    }

    /// Capture the current goal inputs as the "last recalculated" baseline so the nudge clears.
    private func markGoalsRecalculated() {
        UserDefaults.standard.set(profile.goalInputSignature, forKey: Self.lastRecalcGoalSignatureKey)
    }

    /// A goal row (calories or a macro). Tap the row to edit the value; tap the lock icon to lock it.
    /// Locking a macro keeps it fixed during a rebalance; locking calories holds the calorie total
    /// when a macro is edited. Lock controls are disabled while Adaptive Goals is on (it auto-
    /// recalculates and would overwrite). `macro == nil` means the calories row.
    @ViewBuilder
    private func lockableGoalRow(icon: String, label: String, valueText: String, macro: AutoBalanceMacro?, sheet: ActiveSheet) -> some View {
        let locked = macro.map { profile.isMacroLocked($0) } ?? profile.isCaloriesLocked
        // The lock glyph is a read-only indicator. Saving a value locks it; the picker's "Reset to
        // Auto-balance" releases it. Tapping the row opens the picker (or explains, when Adaptive is
        // on and editing would be overwritten weekly).
        Button {
            if adaptiveGoalsEnabled {
                showAdaptiveGoalsLockHint()
            } else {
                activeSheet = sheet
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(AppColors.calorie)
                    .frame(width: 22)
                AdaptiveLabelValue {
                    Text(LocalizedDisplayText.text(label))
                        .foregroundStyle(.primary)
                        .avoidsMidWordBreak()
                } value: {
                    Text(valueText)
                        .foregroundStyle(.secondary)
                        .avoidsMidWordBreak()
                }
                Image(systemName: locked ? "lock.fill" : "lock.open")
                    .font(.footnote)
                    .foregroundStyle(locked ? AppColors.calorie : .secondary)
                    .opacity(adaptiveGoalsEnabled ? 0.3 : 1)
                    .accessibilityLabel(locked ? "Locked" : "Unlocked")
            }
        }
        .buttonStyle(.plain)
    }

    /// Explain why the goals section is read-only while Adaptive Goals owns the targets.
    private func showAdaptiveGoalsLockHint() {
        showAdaptiveGoalAlert(
            title: "Adaptive Goals Is On",
            message: "Turn off Adaptive Goals to lock or set your own calories and macros. While it's on, JL Physical recalculates them for you each week."
        )
    }

    /// Apply a calorie edit: locked macros stay, unlocked macros rescale to the new total. Saving a
    /// value the user chose locks it (the lock icon then releases it).
    private func setCalories(to value: Int) {
        profile.applyCaloriesEdit(value)
        profile.caloriesLocked = true
        saveProfile()
    }

    /// Apply a macro edit through the rebalance engine, then lock the macro the user just set
    /// (honoring the max-2 cap — silently left unlocked if two macros are already locked). When
    /// calories is locked and neither other macro can absorb the change, the edit is rejected.
    private func setMacro(_ macro: AutoBalanceMacro, to value: Int) {
        guard profile.applyMacroEdit(macro, grams: value) else {
            showAutoMacroEditAlert = true
            return
        }
        if !profile.isMacroLocked(macro) {
            _ = profile.toggleMacroLock(macro)
        }
        saveProfile()
    }

    /// "Reset to Auto-balance" from the picker: release the macro's lock and re-derive it as the
    /// balancing remainder.
    private func resetMacroLock(_ macro: AutoBalanceMacro) {
        profile.resetMacroToBalance(macro)
        saveProfile()
    }

    /// "Reset to Auto-balance" from the calories picker: release the calories lock and snap the
    /// total to the sum of the macros.
    private func resetCaloriesLock() {
        profile.resetCaloriesToBalance()
        saveProfile()
    }

    private func recalculateGoalsNow() {
        Task { await recalculateGoalsWithAI() }
    }

    /// AI-driven goal recalculation. Sends the profile + the app's formulas to the user's
    /// selected provider and applies the returned calorie
    /// and protein/fat targets; carbs auto-balances so totals stay consistent. AI-only — when
    /// the provider is unavailable (no key / offline / bad response) the
    /// existing goals are left unchanged and the user is told to fix their provider/key, with
    /// NO silent formula fallback. Then recomputes the optional "Other Nutrients"
    /// (fiber/sugar/sodium/…) via AI, leaving them untouched if that call fails (no clobbering
    /// of user customizations). The whole recalc is aborted if the user edits a goal input
    /// mid-call. Food calorie estimation is untouched.
    private func recalculateGoalsWithAI() async {
        guard !isRecalculatingGoals else { return }
        isRecalculatingGoals = true
        defer { isRecalculatingGoals = false }

        // Snapshot the inputs the AI computes against. The profile is shared (ProfileStore)
        // and can be reloaded/edited on the main actor during the await, so we apply results
        // only if the calc-relevant inputs are still unchanged — otherwise the concurrent
        // edit (which already reset goals) wins, avoiding a stale/lost-update.
        let snapshot = profile
        let energyBurnSnapshot = energyBurnEnabled
        let healthKitSnapshot = healthKitEnabled
        let healthEnergy = await measuredEnergyHistory()
        // Energy Burn toggle: when on, anchor maintenance to the user's measured Apple Health burn.
        let measuredTdee = measuredEnergyTdee(for: snapshot, history: healthEnergy)
        let evidence = makeGoalEvidence(profile: snapshot, healthEnergy: healthEnergy)
        guard energyBurnEnabled == energyBurnSnapshot,
              healthKitEnabled == healthKitSnapshot
        else { return }
        do {
            let result = try await GeminiService.calculateGoals(
                profile: snapshot,
                measuredTdee: measuredTdee,
                measurement: bodyMeasurementStore.latestEntry,
                evidence: evidence,
                heightMetric: heightMetric,
                weightMetric: weightMetric
            )
            guard goalInputsUnchanged(snapshot, profile),
                  energyBurnEnabled == energyBurnSnapshot,
                  healthKitEnabled == healthKitSnapshot
            else { return }
            // Apply the AI's calorie + protein targets. Protein is the AI's choice within a range
            // near the activity multiplier (it can flex with the goal + history), not a rigid lock.
            // Carbs and fat stay auto-balanced (unlocked) and absorb the remaining calories.
            profile.customCalories = result.calories
            profile.customProtein = result.protein
            profile.customCarbs = result.carbs
            profile.customFat = result.fat
            profile.autoBalanceMacro = nil
            profile.clearLocks()
            saveProfile()
            markGoalsRecalculated()
            if adaptiveGoalsEnabled {
                // A successful manual run satisfies this week's Adaptive check; otherwise one tap
                // can be followed by a second identical provider request on the next foreground.
                AdaptiveGoalSettings.markCheckedToday()
            }
        } catch {
            guard goalInputsUnchanged(snapshot, profile),
                  energyBurnEnabled == energyBurnSnapshot,
                  healthKitEnabled == healthKitSnapshot
            else { return }
            // Goals are AI-only now — no formula fallback. Leave the existing goals
            // untouched and tell the user so they can fix their provider/key and retry.
            showAdaptiveGoalAlert(
                title: "Couldn't Recalculate",
                message: "JL Physical couldn't reach your AI provider, so your goals are unchanged. Check your AI provider and API key in Settings, then try Recalculate again."
            )
            return
        }

        // Also recompute the optional "Other Nutrients" (fiber, sugar, sodium, …) via AI,
        // falling back to the standard defaults when AI is unavailable. These live in a
        // separate store from the calorie/macro goals.
        do {
            let suggested = try await GeminiService.suggestOptionalNutrientGoals(
                profile: profile,
                currentGoals: OptionalNutrientGoals.current,
                heightMetric: heightMetric,
                weightMetric: weightMetric
            )
            OptionalNutrientGoals.save(suggested)
        } catch {
            // AI unavailable — leave the existing Other Nutrients goals untouched rather than
            // clobbering any user customizations with defaults.
        }
        // Note: we do NOT chain Adaptive here. Adaptive Goals now *is* this same calculation on a
        // weekly timer, so chaining would fire a second identical AI call.
    }

    /// Discard an in-flight AI result after *any* profile or target edit. Comparing only formula
    /// inputs would still overwrite a user's concurrent calorie/macro/lock changes.
    private func goalInputsUnchanged(_ a: UserProfile, _ b: UserProfile) -> Bool {
        a == b
    }

    private func handleHealthKitToggle(_ enabled: Bool) {
        if enabled {
            Task {
                let authorized = await healthKitManager.requestAuthorization()
                if authorized {
                    healthKitManager.writeWeight(kg: profile.weightKg, date: .now)
                    healthKitManager.writeHeight(cm: profile.heightCm)
                    if let bf = profile.bodyFatPercentage {
                        healthKitManager.writeBodyFat(fraction: bf)
                    }
                    let measurements = await healthKitManager.fetchLatestBodyMeasurements()
                    if let kg = measurements.weight, abs(profile.weightKg - kg) > 0.01 {
                        profile.weightKg = kg
                    }
                    if let cm = measurements.height, abs(profile.heightCm - cm) > 0.1 {
                        profile.heightCm = cm
                    }
                    if let bf = measurements.bodyFat {
                        profile.bodyFatPercentage = bf
                    }
                    if let dob = measurements.dob {
                        profile.birthday = dob
                    }
                    if let sex = measurements.sex {
                        switch sex {
                        case .male: profile.gender = .male
                        case .female: profile.gender = .female
                        default: break
                        }
                    }
                    saveProfile()
                    healthKitManager.startBodyMeasurementObserver()
                    healthKitManager.backfillNutritionIfNeeded(
                        entries: foodStore.entries,
                        currentEntryIDs: { Set(foodStore.entries.map(\.id)) }
                    )
                    healthKitManager.synchronizeWorkoutBurnsWithHealthKit(
                        existing: { strengthWorkoutStore.workoutBurnSessions },
                        mergeBatch: { sessions in
                            strengthWorkoutStore.importWorkoutBurnSessions(sessions)
                        }
                    )
                    healthKitManager.synchronizeImportedWorkoutsWithHealthKit { workouts, queryStart in
                        importedHealthWorkoutStore.synchronize(with: workouts, queryStart: queryStart)
                    }
                } else {
                    healthKitEnabled = false
                }
            }
        } else {
            healthKitManager.stopObserver()
        }
    }

    private func handleAdaptiveGoalsToggle(_ enabled: Bool, wasEnabled: Bool) {
        if enabled {
            // Adaptive owns the targets while on and auto-recalculates — clear any user locks now so
            // the (disabled) lock controls read as unlocked, even before the weekly run lands.
            if profile.isCaloriesLocked || profile.lockedMacroCount > 0 {
                profile.clearLocks()
                saveProfile()
            }
            Task { await applyAdaptiveGoalsIfDue(force: !wasEnabled, showAlert: true) }
        } else {
            if AdaptiveGoalSettings.restorePreviousTargets(to: &profile) {
                saveProfile()
            }
            AdaptiveGoalSettings.clearPreviousTargets()
        }
    }

    /// Energy Burn is an input switch for the goal calc. Enabling requires Apple Health with enough
    /// data (mirrors Android) — otherwise we revert the toggle and tell the user instead of running
    /// an anchorless recalc. On a genuine enable/disable we re-run the calc so the new (or removed)
    /// measured anchor takes effect immediately, exactly like tapping Recalculate.
    private func handleEnergyBurnToggle(_ enabled: Bool) {
        // A programmatic revert (failed enable, below) re-fires this onChange — skip that pass.
        if energyBurnToggleReverting { energyBurnToggleReverting = false; return }
        if enabled {
            guard healthKitEnabled else {
                energyBurnToggleReverting = true
                energyBurnEnabled = false
                showAdaptiveGoalAlert(title: "Apple Health Needed", message: "Energy Burn uses your measured calories burned from Apple Health. Connect Apple Health first, then turn Energy Burn on.")
                return
            }
            Task {
                if await healthKitManager.fetchRecentEnergySummary(days: 14) == nil {
                    energyBurnToggleReverting = true
                    energyBurnEnabled = false
                    showAdaptiveGoalAlert(title: "Not Enough Health Data", message: "JL Physical needs at least 3 recent days of Apple Health energy data before it can use your measured burn.")
                    return
                }
                await recalculateGoalsWithAI()
            }
        } else {
            Task { await recalculateGoalsWithAI() }
        }
    }

    /// Energy Burn toggle resolved to a number from the recent Apple Health window: measured total
    /// when sufficiently available, otherwise measured active energy plus formula BMR. Returns nil
    /// when Energy Burn is off, Health is disconnected, or there isn't enough data.
    private func measuredEnergyTdee(
        for profile: UserProfile,
        history: [HealthEnergyDay]
    ) -> Int? {
        guard energyBurnEnabled, healthKitEnabled else { return nil }
        guard let summary = HealthKitManager.energySummary(from: history, requestedDays: 14) else {
            return nil
        }
        return summary.totalAverageCalories ?? (Int(profile.bmr.rounded()) + summary.activeAverageCalories)
    }

    /// Daily measured energy is only included while Energy Burn and Apple Health are enabled.
    /// HealthKitManager removes JL Physical's own estimated workout samples before aggregation.
    private func measuredEnergyHistory() async -> [HealthEnergyDay] {
        guard energyBurnEnabled, healthKitEnabled else { return [] }
        let history = await healthKitManager.fetchRecentEnergyHistory(days: 14)
        // A user can opt out while HealthKit is suspended. Never pass the completed fetch to an
        // AI provider after either switch has been turned off.
        guard energyBurnEnabled, healthKitEnabled else { return [] }
        return history
    }

    private func makeGoalEvidence(profile: UserProfile, healthEnergy: [HealthEnergyDay]) -> GoalEvidence {
        GoalEvidence.build(
            foods: foodStore.entries,
            weights: weightStore.bodyWeightEntries,
            bodyFatEntries: bodyFatStore.entries,
            workoutSessions: strengthWorkoutStore.completedSessions,
            bodyMeasurements: bodyMeasurementStore.entries,
            healthEnergy: healthEnergy,
            profile: profile
        )
    }

    /// Adaptive Goals: automatically re-runs the FULL AI goal calculation (the same one the
    /// Recalculate button uses) about once a week, from the latest logged food + weight trend
    /// (hit-and-trial) and — when Energy Burn is on — the measured Health maintenance anchor.
    /// Silent and non-destructive on AI failure (keeps existing goals; marks checked so it doesn't
    /// retry every app open).
    private func applyAdaptiveGoalsIfDue(force: Bool, showAlert: Bool) async {
        guard adaptiveGoalsEnabled, !isApplyingAdaptiveGoals else { return }
        guard force || AdaptiveGoalSettings.shouldCheckThisWeek() else { return }

        isApplyingAdaptiveGoals = true
        defer { isApplyingAdaptiveGoals = false }

        let snapshot = profile
        let energyBurnSnapshot = energyBurnEnabled
        let healthKitSnapshot = healthKitEnabled
        let healthEnergy = await measuredEnergyHistory()
        let measuredTdee = measuredEnergyTdee(for: snapshot, history: healthEnergy)
        let evidence = makeGoalEvidence(profile: snapshot, healthEnergy: healthEnergy)
        guard adaptiveGoalsEnabled,
              energyBurnEnabled == energyBurnSnapshot,
              healthKitEnabled == healthKitSnapshot
        else { return }
        do {
            let result = try await GeminiService.calculateGoals(
                profile: snapshot,
                measuredTdee: measuredTdee,
                measurement: bodyMeasurementStore.latestEntry,
                evidence: evidence,
                heightMetric: heightMetric,
                weightMetric: weightMetric
            )
            guard adaptiveGoalsEnabled,
                  goalInputsUnchanged(snapshot, profile),
                  energyBurnEnabled == energyBurnSnapshot,
                  healthKitEnabled == healthKitSnapshot
            else { return }
            AdaptiveGoalSettings.savePreviousTargetsIfNeeded(from: profile)
            profile.customCalories = result.calories
            profile.customProtein = result.protein
            profile.customCarbs = result.carbs
            profile.customFat = result.fat
            profile.autoBalanceMacro = nil
            profile.clearLocks()
            saveProfile()
            markGoalsRecalculated()
            AdaptiveGoalSettings.markCheckedToday()
            if showAlert {
                showAdaptiveGoalAlert(title: "Adaptive Goals", message: "Updated to \(result.calories) kcal from your latest data." + (result.reason.map { " \($0)" } ?? ""))
            }
        } catch {
            guard adaptiveGoalsEnabled,
                  energyBurnEnabled == energyBurnSnapshot,
                  healthKitEnabled == healthKitSnapshot
            else { return }
            // AI unavailable — keep existing goals. Mark checked so the auto-run doesn't hammer a
            // misconfigured provider on every app open; the user can still Recalculate manually.
            AdaptiveGoalSettings.markCheckedToday()
            if showAlert {
                showAdaptiveGoalAlert(title: "Adaptive Goals", message: "Couldn't reach your AI provider — your goals are unchanged. Check your AI provider and API key in Settings.")
            }
        }
    }

    private func showAdaptiveGoalAlert(title: String, message: String) {
        adaptiveGoalAlertTitle = title
        adaptiveGoalAlertMessage = message
        showAdaptiveGoalAlert = true
    }

}

private struct AllergenSensitivitiesDetailView: View {
    let onSave: ([String]) -> Void

    @State private var allergens: [String]
    @State private var value = ""
    @State private var pendingDeletion: String?
    @State private var showImportSource = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isImportingLabReport = false
    @State private var importErrorMessage: String?
    @State private var pendingImportCandidates: [String]?
    @State private var selectedImportNames: Set<String> = []

    init(current: [String], onSave: @escaping ([String]) -> Void) {
        self.onSave = onSave
        _allergens = State(initialValue: current)
    }

    var body: some View {
        List {
            Section {
                if allergens.isEmpty {
                    Text("No sensitivities added")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allergens, id: \.self) { allergen in
                        HStack {
                            Text(allergen)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                pendingDeletion = allergen
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                            .tint(.red)
                        }
                    }
                }
            } header: {
                Text("Sensitivities")
            } footer: {
                Text("Used for local label checks. Swipe left to delete. Changes save automatically. Results never indicate that a food is safe.")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                Button {
                    showImportSource = true
                } label: {
                    Label("Import from lab report", systemImage: "doc.text.viewfinder")
                }
                .disabled(isImportingLabReport)
                .foregroundStyle(AppColors.calorie)
            } footer: {
                Text("Extracts possible sensitizations from an ISAC/ALEX-style allergy blood-test report for local checks only. Not a medical diagnosis — confirm every name before adding.")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                TextField("Type an allergen", text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { addCurrentValue() }
            } footer: {
                Text("Press Return to add.")
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Allergen sensitivities")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isImportingLabReport {
                ZStack {
                    Color.black.opacity(0.28).ignoresSafeArea()
                    ProgressView("Reading lab report…")
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .confirmationDialog("Import from lab report", isPresented: $showImportSource, titleVisibility: .visible) {
            Button("Choose Photo") { showPhotoPicker = true }
            Button("Choose File") { showFileImporter = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pick a photo or PDF of your allergy blood-test report.")
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            selectedPhotoItem = nil
            Task { await importLabReport(from: item) }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false,
            onCompletion: { result in
                Task { await importLabReport(from: result) }
            }
        )
        .sheet(isPresented: Binding(
            get: { pendingImportCandidates != nil },
            set: { if !$0 { clearPendingImport() } }
        )) {
            LabReportAllergenConfirmationSheet(
                candidates: pendingImportCandidates ?? [],
                selectedNames: $selectedImportNames,
                onCancel: { clearPendingImport() },
                onAdd: { selected in
                    mergeImportedAllergens(selected)
                    clearPendingImport()
                }
            )
        }
        .alert("Delete Allergen?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let pendingDeletion {
                    removeAllergen(pendingDeletion)
                }
                pendingDeletion = nil
            }
        } message: {
            Text("Remove \(pendingDeletion ?? "this allergen") from your sensitivities?")
        }
        .alert("Unable to Import", isPresented: Binding(
            get: { importErrorMessage != nil },
            set: { if !$0 { importErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importErrorMessage = nil }
        } message: {
            Text(importErrorMessage ?? "The lab report could not be read.")
        }
    }

    private func persist(_ next: [String]) {
        allergens = next
        onSave(next)
    }

    private func addCurrentValue() {
        let next = value.trimmingCharacters(in: .whitespacesAndNewlines)
        value = ""
        guard !next.isEmpty else { return }
        guard !allergens.contains(where: { $0.caseInsensitiveCompare(next) == .orderedSame }) else { return }
        persist(allergens + [next])
    }

    private func removeAllergen(_ allergen: String) {
        persist(allergens.filter { $0 != allergen })
    }

    private func mergeImportedAllergens(_ names: [String]) {
        var next = allergens
        var existing = Set(next.map { $0.lowercased() })
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, existing.insert(trimmed.lowercased()).inserted else { continue }
            next.append(trimmed)
        }
        persist(next)
    }

    @MainActor
    private func beginImport() {
        isImportingLabReport = true
        importErrorMessage = nil
    }

    @MainActor
    private func presentImportResults(_ names: [String]) {
        isImportingLabReport = false
        if names.isEmpty {
            importErrorMessage = "No clearly positive or elevated sensitizations were found in this report."
            return
        }
        selectedImportNames = Set(names)
        pendingImportCandidates = names
    }

    @MainActor
    private func failImport(_ error: Error) {
        isImportingLabReport = false
        importErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func clearPendingImport() {
        pendingImportCandidates = nil
        selectedImportNames = []
    }

    private func runLabReportImport(_ loadImages: () async throws -> [UIImage]) async {
        await MainActor.run { beginImport() }
        do {
            let images = try await loadImages()
            guard !images.isEmpty else { throw GeminiService.AnalysisError.imageConversionFailed }
            let names = try await GeminiService.extractAllergensFromLabReport(images: images)
            await MainActor.run { presentImportResults(names) }
        } catch {
            await MainActor.run { failImport(error) }
        }
    }

    private func importLabReport(from item: PhotosPickerItem) async {
        await runLabReportImport {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw GeminiService.AnalysisError.imageConversionFailed
            }
            return [image]
        }
    }

    private func importLabReport(from result: Result<[URL], Error>) async {
        let url: URL
        switch result {
        case .success(let urls):
            guard let first = urls.first else { return }
            url = first
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError {
                return
            }
            await MainActor.run { failImport(error) }
            return
        }

        await runLabReportImport {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return try labReportImages(from: data, url: url)
        }
    }

    private func labReportImages(from data: Data, url: URL) throws -> [UIImage] {
        let isPDF = url.pathExtension.lowercased() == "pdf"
            || (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .pdf)) == true
        if isPDF {
            return rasterizePDFPages(data: data, maxPages: 3)
        }
        guard let image = UIImage(data: data) else {
            throw GeminiService.AnalysisError.imageConversionFailed
        }
        return [image]
    }

    private func rasterizePDFPages(data: Data, maxPages: Int) -> [UIImage] {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { return [] }
        let scale: CGFloat = 2
        return (0..<min(document.pageCount, maxPages)).compactMap { index in
            guard let page = document.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            return UIGraphicsImageRenderer(size: size).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context.cgContext)
                context.cgContext.restoreGState()
            }
        }
    }
}

private struct LabReportAllergenConfirmationSheet: View {
    let candidates: [String]
    @Binding var selectedNames: Set<String>
    let onCancel: () -> Void
    let onAdd: ([String]) -> Void

    private var allSelected: Bool {
        !candidates.isEmpty && candidates.allSatisfy(selectedNames.contains)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        selectedNames = allSelected ? [] : Set(candidates)
                    }
                    .foregroundStyle(AppColors.calorie)
                }
                .listRowBackground(AppColors.appCard)

                Section {
                    ForEach(candidates, id: \.self) { name in
                        Toggle(isOn: selectionBinding(for: name)) {
                            Text(name)
                        }
                        .tint(AppColors.calorie)
                    }
                } header: {
                    Text("Possible sensitizations")
                } footer: {
                    Text("Confirm which names to add. This is not a medical diagnosis and never means a food is safe.")
                }
                .listRowBackground(AppColors.appCard)
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.appBackground)
            .navigationTitle("Confirm allergens")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Selected") {
                        onAdd(candidates.filter(selectedNames.contains))
                    }
                    .disabled(selectedNames.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func selectionBinding(for name: String) -> Binding<Bool> {
        Binding(
            get: { selectedNames.contains(name) },
            set: { isOn in
                if isOn {
                    selectedNames.insert(name)
                } else {
                    selectedNames.remove(name)
                }
            }
        )
    }
}

#Preview {
    ContentView()
        .environment(FoodStore())
        .environment(WeightStore())
        .environment(WorkoutDraftStore())
}
