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
            RestTimerSheet(defaultSeconds: 90)
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
                    StepsView(loadsHealthData: false)
                }
            }
        }
        // Same screen scrolled into the history list via a taller canvas.
        try await eachSize("06b-daily-steps-full", heightMultiplier: 2.2) { _ in
            VisualQATabShell(selected: .train) {
                VisualQAPushed(rootTitle: "Train") {
                    StepsView(loadsHealthData: false)
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
        // ProfileView's init is file-private to ContentView, so render the real ContentView
        // and switch its tab bar to More the way a tap would.
        PostUpdatePrompts.markAllSeenForFreshInstall()
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
            TextFoodInputView(onCancel: {}, onSubmit: { _ in })
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
        // ProfileView (which hosts the full AI Providers & Fallbacks list) has a
        // file-private init in ContentView, so render its On-Device Model section
        // with the real Gemma4ModelSettingsView in the download-in-progress state.
        try await eachSize("23-ai-providers-on-device-download") { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") { VisualQAOnDeviceModelSection() }
            }
        }
    }

    // MARK: - Rendering

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
        defer { VisualQAFixtures.uninstall() }
        for size in Self.sizes {
            let stores = VisualQAStores()
            let root = stores.inject(content(size.size), dynamicType: size.size)
            let sheetView = sheet.map { AnyView(stores.inject(AnyView($0()), dynamicType: size.size)) }
            let secondView = secondSheet.map { AnyView(stores.inject(AnyView($0()), dynamicType: size.size)) }
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
        window.frame = CGRect(x: 0, y: 0, width: screen.width, height: (screen.height * heightMultiplier).rounded())
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
        let bounds = UIScreen.main.bounds
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

/// Mirrors the "On-Device Model" block of Settings > AI Providers & Fallbacks.
struct VisualQAOnDeviceModelSection: View {
    var body: some View {
        List {
            Section {
                onDeviceHeader
                Gemma4ModelSettingsView(previewState: .downloading(0.42)) {}
            }
            .listRowBackground(AppColors.appCard)

            Section {
                onDeviceHeader
                Gemma4ModelSettingsView(previewState: .notDownloaded) {}
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(IronTheme.canvas)
        .navigationTitle("AI Providers & Fallbacks")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var onDeviceHeader: some View {
        Label(
            LocalModelStrings.text("settings.onDeviceModel", defaultValue: "On-Device Model"),
            systemImage: "iphone.gen3.radiowaves.left.and.right"
        )
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .foregroundStyle(AppColors.calorie)
        .textCase(.uppercase)
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
    let cloudBackup: CloudBackupService

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
        cloudBackup = CloudBackupService(defaults: defaults)
        bodyFat = BodyFatStore(observesExternalChanges: false)
        bodyMeasurement = BodyMeasurementStore()
        notifications = NotificationManager()
        healthKit = HealthKitManager()
        profile = ProfileStore()
        chat = ChatStore()

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
            .environment(cloudBackup)
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
    private static var savedSettings: NeonBridgeSettings?

    static func install() {
        VisualQAStubStorage.setResponses(buildResponses())
        URLProtocol.registerClass(VisualQAStubProtocol.self)
        if savedSettings == nil {
            savedSettings = NeonBridgeService.shared.settings
        }
        NeonBridgeService.shared.settings = NeonBridgeSettings(baseURL: "https://\(host)", apiKey: nil)
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
        var date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
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
        return .now
    }

    static func liftingDay() -> ProgramV2Day {
        TrainingProgramBody.bundledV2().days[0].asProgramV2Day()
    }

    static func isoDay(offset: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: .now) ?? .now
        return formatter.string(from: date)
    }

    static func seedSteps() {
        let values: [Int?] = [161, 4_820, 7_842, 8_773, 12_973, 1_294, 0]
        let service = StepsTrackingService.shared
        service.todaySteps = values[0] ?? 0
        service.last7Days = values.enumerated().map { index, steps in
            StepsDay(
                date: isoDay(offset: index),
                steps: steps,
                met: steps.map { $0 >= StepsView.dailyGoal },
                logged: steps != nil,
                source: "healthkit",
                device: "iPhone",
                origin: nil
            )
        }
        service.lastSyncDate = Date().addingTimeInterval(-600)
        service.lastSyncError = nil
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
            "/api/programs": json(TrainingProgramListResponse(programs: [program])),
            "/api/programs/active": json(program),
            "/api/programs/\(program.id)": json(program),
            "/api/peptides/today": (200, Data(peptideTodayJSON().utf8)),
            "/api/peptides/inventory": (200, Data(peptideInventoryJSON.utf8)),
            "/api/peptides/schedules": (200, Data(peptideSchedulesJSON.utf8)),
        ]
    }
}

/// Thread-safe holder the URLProtocol reads from URLSession's queue.
nonisolated final class VisualQAStubStorage: @unchecked Sendable {
    static let host = "visual-qa.invalid"
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
