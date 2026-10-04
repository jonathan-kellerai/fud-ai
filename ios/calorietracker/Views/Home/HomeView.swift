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

// MARK: - Home View (Main Dashboard)
struct HomeView: View {
    let quickActionRequest: QuickActionRequest?
    let onQuickActionHandled: (UUID) -> Void
    var foodLogMethodRequest: FoodLogMethodRequest?
    var onFoodLogMethodHandled: (UUID) -> Void = { _ in }
    @Environment(FoodStore.self) private var foodStore
    @Environment(WaterStore.self) private var waterStore
    @Environment(FastingStore.self) private var fastingStore
    @Environment(NotificationManager.self) private var notificationManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var homeRefreshToken = 0
    @State private var showCamera = false
    @State private var showBarcodeScanner = false
    @State private var capturedImage: UIImage?
    @State private var cameraMode: CameraMode = .snapFood
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showHostedQuotaPaywall = false
    @State private var showHostedPaywall = false
    @State private var showHostedCredits = false
    private enum RetryRequest {
        case analysis(images: [UIImage], mode: CameraMode, description: String?, progressiveMeal: Bool)
        case text(String)
        case barcode(String)
    }
    @State private var retryRequest: RetryRequest?
    @State private var lastEstimateRequest: RetryRequest?
    @State private var reestimateUsed = false
    /// The in-flight photo/text/barcode analysis behind the analyzing sheet, so Cancel can abort it.
    @State private var analysisTask: Task<Void, Never>?
    @State private var selectedDate: Date = .now
    @State private var showVoicePopover = false
    @State private var showTextPopover = false
    @State private var showManualPopover = false
    @State private var showSiriPhrases = false
    @State private var savedMealsMode: SavedMealsMode?
    @State private var showCopyFromDaySheet = false
    @State private var pendingContextImage: UIImage?
    @State private var captureImages: [UIImage] = []
    @State private var isImportingPhotos = false
    @State private var showMultiPhotoCaptureSheet = false
    @State private var contextDescription: String = ""
    @State private var showContextSheet = false

    enum ActiveSheet: String, Identifiable {
        case analyzing, foodResult, analyzingText, lookingUpBarcode, editFood, importSharedMeal
        /// Analyzing and Review Food share one identity so a fast model
        /// response does not dismiss + re-present the sheet. SwiftUI drops
        /// that swap on slower phones (iPhone 11 / #396).
        var id: String {
            switch self {
            case .analyzing, .analyzingText, .lookingUpBarcode, .foodResult:
                return "foodLog"
            case .editFood, .importSharedMeal:
                return rawValue
            }
        }
    }
    private enum FoodLogPhase: Hashable {
        case analyzing, analyzingText, lookingUpBarcode, result
        var isLoading: Bool { self != .result }
    }
    @State private var activeSheet: ActiveSheet?
    @State private var foodLogPhase: FoodLogPhase = .result
    @State private var editingEntry: FoodEntry?
    @State private var pendingDiaryDeletion: DiaryDeletion?

    private enum DiaryDeletion {
        case food(FoodEntry), water(WaterEntry), fasting(FastingSession)

        var title: String {
            switch self {
            case .food: return "Delete Food Log?"
            case .water: return "Delete Water Log?"
            case .fasting: return "Delete Fasting Log?"
            }
        }

        var message: String {
            switch self {
            case .food: return "This removes the food from your diary. Saved favorites are kept."
            case .water: return "This removes the water entry from your diary."
            case .fasting: return "This removes the completed fast from your diary."
            }
        }
    }
    @State private var selectedFoodIDs: Set<UUID> = []
    private var isDiaryDeletionPresented: Binding<Bool> {
        Binding<Bool>(
            get: { pendingDiaryDeletion != nil },
            set: { presented in
                if !presented { pendingDiaryDeletion = nil }
            }
        )
    }

    private func confirmDiaryDeletion(_ target: DiaryDeletion) {
        switch target {
        case .food(let entry): foodStore.deleteEntry(entry)
        case .water(let entry): waterStore.delete(id: entry.id)
        case .fasting(let session):
            fastingStore.delete(id: session.id)
            refreshFastingGoalNotification()
        }
        pendingDiaryDeletion = nil
    }

    private var isFoodSelectionMode: Bool { !selectedFoodIDs.isEmpty }
    private var foodSelectionSummary: some View {
        HStack(spacing: 8) {
            Button {
                selectedFoodIDs.removeAll()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Cancel selection")

            Text("\(selectedFoodIDs.count) selected")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var combineFoodButton: some View {
        Button {
            let ids = selectedFoodIDs
            if let combined = foodStore.combineIntoMeal(ids: ids) {
                selectedFoodIDs.removeAll()
                editingEntry = combined
                activeSheet = .editFood
            } else {
                selectedFoodIDs.removeAll()
                errorMessage = "Can't combine foods while fasting is active."
                showError = true
            }
        } label: {
            Text("Combine")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .fixedSize()
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .foregroundStyle(AppColors.calorie.opacity(selectedFoodIDs.count < 2 ? 0.45 : 1))
                .background(AppColors.calorie.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(selectedFoodIDs.count < 2)
        .accessibilityLabel("Combine into Meal")
    }

    @State private var pendingSharedMeals: [FoodEntry] = []

    @State private var currentFoodResult: GeminiService.FoodAnalysis?
    @State private var savedMatchContext: SavedMatchContext?
    private let routerHandoff = RouterHandoff.shared
    @State private var currentImage: UIImage?
    @State private var currentImages: [UIImage] = []
    @State private var currentEmoji: String?
    @State private var currentFoodSource: FoodSource = .snapFood
    @State private var showNutritionDetail = false
    @State private var showCustomWaterLog = false
    @State private var showFastingStart = false
    @State private var editingFastingSession: FastingSession?
    @State private var showFastingQuickActionDisabled = false
    @State private var showFoodLoggingBlocked = false
    @State private var hasPresentedFoodDestination = false
    @State private var didPrewarmFoodDestinations = false
    // Bumped each time the app is opened (cold launch = 1, then +1 on every
    // return from background). Drives the gauge + macro "fill from zero" reveal.
    // Not bumped on tab switches or data edits, so it only plays on app open.
    @AppStorage("weightUnit") private var weightUnitRaw = "lbs"
    @AppStorage(FoodLogSortOrder.storageKey) private var foodLogSortOrderRaw = FoodLogSortOrder.defaultOrder.rawValue
    @AppStorage(HomeTopNutrient.storageKey) private var homeTopNutrientsRaw = HomeTopNutrient.storageValue(for: HomeTopNutrient.defaultSelection)
    @AppStorage(WaterSettings.enabledKey) private var waterTrackingEnabled = false
    @AppStorage(WaterSettings.dailyGoalKey) private var waterDailyGoal = WaterSettings.defaultDailyGoalMl
    @AppStorage(WaterSettings.unitKey) private var waterUnitRaw = WaterUnit.defaultUnit.rawValue
    @AppStorage(FastingSettings.enabledKey) private var fastingTrackingEnabled = false
    @AppStorage(FastingSettings.defaultGoalMinutesKey) private var fastingDefaultGoalMinutes = FastingSettings.defaultGoalMinutes
    @AppStorage(FastingSettings.notificationEnabledKey) private var fastingGoalNotificationEnabled = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @Environment(ProfileStore.self) private var profileStore

    /// Force a body re-evaluation whenever profileStore.profile changes by reading it
    /// at the top of body. SwiftUI's @Observable tracking sometimes misses the access
    /// when the read is buried in a computed property; explicit access guarantees it.
    private var userProfile: UserProfile { profileStore.profile }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var foodLogSortOrder: FoodLogSortOrder { FoodLogSortOrder.order(for: foodLogSortOrderRaw) }
    private var waterUnit: WaterUnit { WaterUnit(rawValue: waterUnitRaw) ?? .defaultUnit }
    private var logDateForSelectedDay: Date { logDate(on: selectedDate) }

    private func logDate(on day: Date, now: Date = .now) -> Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return now }

        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        var components = DateComponents()
        components.year = dayComponents.year
        components.month = dayComponents.month
        components.day = dayComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        components.nanosecond = timeComponents.nanosecond
        return calendar.date(from: components) ?? day
    }

    private func logWater(_ milliliters: Int) {
        _ = waterStore.add(milliliters: milliliters, on: logDateForSelectedDay)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func refreshFastingGoalNotification() {
        notificationManager.scheduleFastingGoal(
            enabled: notificationsEnabled && fastingTrackingEnabled && fastingGoalNotificationEnabled,
            session: fastingStore.activeSession
        )
    }

    private func startFast(goalMinutes: Int) {
        guard fastingStore.start(goalMinutes: goalMinutes) != nil else { return }
        refreshFastingGoalNotification()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @discardableResult
    private func endFast() -> Bool {
        guard fastingStore.endActive() != nil else { return false }
        notificationManager.cancelFastingGoal()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        return true
    }

    @discardableResult
    private func canBeginFoodLogging() -> Bool {
        guard fastingStore.activeSession == nil else {
            showFoodLoggingBlocked = true
            return false
        }
        return true
    }

    /// Lets the native menu finish its selection before presenting the chosen destination.
    /// The first presentation skips animation so cold setup cannot stretch the handoff;
    /// later selections retain the short transition that already feels responsive.
    private func presentFoodDestination(_ updates: @escaping () -> Void) {
        let shouldAnimate = hasPresentedFoodDestination
        hasPresentedFoodDestination = true

        DispatchQueue.main.async {
            var transaction = Transaction(animation: shouldAnimate ? .easeOut(duration: 0.16) : nil)
            transaction.disablesAnimations = !shouldAnimate
            withTransaction(transaction) {
                updates()
            }
        }
    }

    /// Loads the native menu and media authorization code paths while Home is idle.
    /// Reading authorization status never prompts the user or starts camera/microphone capture.
    /// Photo access is add-only: `readWrite` aborts the process unless
    /// `NSPhotoLibraryUsageDescription` is set, and this app only saves meal photos.
    private func prewarmFoodDestinations() {
        guard !didPrewarmFoodDestinations else { return }
        didPrewarmFoodDestinations = true

        let placeholderAction = UIAction(title: "") { _ in }
        let placeholderSubmenu = UIMenu(title: "", children: [placeholderAction])
        _ = UIMenu(title: "", children: [placeholderSubmenu])

        Task.detached(priority: .utility) {
            _ = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            _ = AVCaptureDevice.authorizationStatus(for: .video)
            _ = SFSpeechRecognizer.authorizationStatus()
        }
    }

    @ViewBuilder
    private var waterQuickMenuItems: some View {
        Button {
            presentFoodDestination {
                showCustomWaterLog = true
            }
        } label: {
            Label("Custom", systemImage: "slider.horizontal.3")
        }
        Button {
            logWater(750)
        } label: {
            Label("3 Glasses (~\(waterUnit.formatted(milliliters: 750)))", systemImage: "drop.fill")
        }
        Button {
            logWater(500)
        } label: {
            Label("2 Glasses (~\(waterUnit.formatted(milliliters: 500)))", systemImage: "drop.fill")
        }
        Button {
            logWater(250)
        } label: {
            Label("1 Glass (~\(waterUnit.formatted(milliliters: 250)))", systemImage: "drop.fill")
        }
    }

    var body: some View {
        homeContent
            .alert(pendingDiaryDeletion?.title ?? "Delete Entry?", isPresented: isDiaryDeletionPresented, presenting: pendingDiaryDeletion) { target in
                Button("Cancel", role: .cancel) { pendingDiaryDeletion = nil }
                Button("Delete", role: .destructive) {
                    confirmDiaryDeletion(target)
                }
            } message: { target in
                Text(target.message)
            }
    }

    private var homeContent: some View {
        // Explicit observation tracking — reads profileStore.profile at body root
        // so SwiftUI invalidates this view on every profile mutation.
        let _ = profileStore.profile
        return NavigationStack {
            homeCoveredDiary
            .interactiveDismissDisabled(foodLogPhase.isLoading && (
                activeSheet == .analyzing || activeSheet == .analyzingText || activeSheet == .lookingUpBarcode
            ))
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
                selectionBehavior: .ordered,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { oldValue, newValue in
                guard !newValue.isEmpty else { return }
                selectedPhotoItems = []
                Task {
                    var imported: [UIImage] = []
                    for item in newValue.prefix(10 - captureImages.count) {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            imported.append(image)
                        }
                    }
                    if !imported.isEmpty {
                        captureImages = Array((captureImages + imported).prefix(10))
                        currentImage = captureImages.first
                        currentImages = captureImages
                        currentEmoji = nil
                        currentFoodSource = .snapFood
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            showMultiPhotoCaptureSheet = true
                        }
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("Retry") { retryLastRequest() }
                Button("Cancel", role: .cancel) { retryRequest = nil }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showHostedQuotaPaywall) {
                HostedQuotaSoftPaywall(
                    onBuyCreditsOrUpgrade: {
                        if RevenueCatManager.shared.hasHostedEntitlement {
                            showHostedCredits = true
                        } else {
                            showHostedPaywall = true
                        }
                    },
                    onSwitchBYOK: {}
                )
            }
            .sheet(isPresented: $showHostedPaywall) {
                HostedPaywallView()
            }
            .sheet(isPresented: $showHostedCredits) {
                HostedCreditsSheet()
            }
            .alert("Food logging paused", isPresented: $showFoodLoggingBlocked) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("End or cancel your active fast before logging food.")
            }
            .alert("Fasting Tracking off", isPresented: $showFastingQuickActionDisabled) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Enable Fasting Tracking in Settings to use this shortcut.")
            }
            .sheet(isPresented: $showNutritionDetail) {
                NutritionDetailView(date: selectedDate, homeTopNutrientsRaw: $homeTopNutrientsRaw)
            }
            .sheet(isPresented: $showCustomWaterLog) {
                WaterCustomAmountSheet(unit: waterUnit, onAdd: logWater)
            }
            .onOpenURL { url in
                if url.scheme == "fudai", url.host == "import-share-image" {
                    checkAndConsumeSharedImage()
                } else if MealShare.handles(url) {
                    // Shared meal — custom scheme or https Universal Link (issue #107).
                    // Universal Links open the app directly (no browser). Confirm before adding.
                    guard canBeginFoodLogging() else { return }
                    guard let meals = MealShare.meals(from: url) else { return }
                    activeSheet = nil
                    pendingSharedMeals = meals
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        activeSheet = .importSharedMeal
                    }
                }
            }
            .onAppear {
                checkAndConsumeSharedImage()
                prewarmFoodDestinations()
            }
            .task(id: quickActionRequest?.id) {
                presentQuickActionIfPossible()
            }
            .task(id: foodLogMethodRequest?.id) {
                presentFoodLogMethodIfPossible()
            }
            .onChange(of: activeSheet) { oldValue, newValue in
                if oldValue != nil && newValue == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        presentQuickActionIfPossible()
                        presentFoodLogMethodIfPossible()
                    }
                } else {
                    presentQuickActionIfPossible()
                    presentFoodLogMethodIfPossible()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    JevCredentials.refresh()
                    checkAndConsumeSharedImage()
                    homeRefreshToken += 1
                    consumeRouterFoodHandoff()
                } else if newPhase == .background {
                    JevRouterTelemetry.shared.flush()
                }
            }
            .onAppear {
                consumeRouterFoodHandoff()
            }
            .onChange(of: routerHandoff.pendingFoodText) { _, _ in
                consumeRouterFoodHandoff()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fudBarcodeAlertScanLabel)) { _ in
                retryRequest = nil
                openCameraForNutritionLabel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fudBarcodeAlertRetry)) { _ in
                retryLastRequest()
            }
            .onReceive(NotificationCenter.default.publisher(for: .fudBarcodeAlertCancel)) { _ in
                retryRequest = nil
            }
        }
    }

    private var homeDiaryList: some View {
            List {
                HomeV2Cards(selectedDate: $selectedDate, refreshToken: homeRefreshToken) {
                    showNutritionDetail = true
                }

                // Unified diary: water and fasting are grouped by their log/end time,
                // but stay excluded from food calories, macros, sharing and favorites.
                // Tracking preferences control new-entry UI, not persisted history.
                // Keep previously logged water and fasting sessions visible after
                // either tracker is disabled so the diary never appears to lose data.
                let diaryFasts = fastingStore.completed(on: selectedDate)
                    + (isToday ? [fastingStore.activeSession].compactMap { $0 } : [])
                let mealGroups = homeDiaryMealGroups(
                    foodEntries: foodStore.entries(for: selectedDate),
                    waterEntries: waterStore.entries(on: selectedDate),
                    fastingSessions: diaryFasts,
                    order: foodLogSortOrder
                )
                if mealGroups.isEmpty {
                    Section(isToday ? "Today's Diary" : "Diary") {
                        Text("No diary entries")
                            .foregroundStyle(.secondary)
                            .listRowBackground(AppColors.appCard)
                    }
                } else {
                    ForEach(mealGroups) { group in
                        Section {
                            ForEach(group.items) { item in
                                Group {
                                    switch item {
                                    case .food(let entry):
                                        HStack(spacing: 12) {
                                            if isFoodSelectionMode {
                                                Image(systemName: selectedFoodIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                                    .font(.title2)
                                                    .foregroundStyle(selectedFoodIDs.contains(entry.id) ? AppColors.calorie : .secondary)
                                            }
                                            FoodRow(entry: entry)
                                        }
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if isFoodSelectionMode {
                                                if selectedFoodIDs.contains(entry.id) {
                                                    selectedFoodIDs.remove(entry.id)
                                                } else {
                                                    selectedFoodIDs.insert(entry.id)
                                                }
                                            } else {
                                                editingEntry = entry
                                                activeSheet = .editFood
                                            }
                                        }
                                        .onLongPressGesture {
                                            selectedFoodIDs.insert(entry.id)
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                            if !isFoodSelectionMode {
                                                Button {
                                                    pendingDiaryDeletion = .food(entry)
                                                } label: {
                                                    Label("Delete", systemImage: "trash.fill")
                                                }
                                                .tint(.red)
                                                Button {
                                                    foodStore.toggleFavorite(entry)
                                                } label: {
                                                    Label(foodStore.isFavorite(entry) ? "Unfavorite" : "Favorite", systemImage: foodStore.isFavorite(entry) ? "heart.slash.fill" : "heart.fill")
                                                }
                                                .tint(AppColors.calorie)
                                            }
                                        }
                                    case .water(let entry):
                                        WaterLogRow(entry: entry, unit: waterUnit)
                                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                                Button {
                                                    pendingDiaryDeletion = .water(entry)
                                                } label: {
                                                    Label("Delete", systemImage: "trash.fill")
                                                }
                                                .tint(.red)
                                            }
                                    case .fasting(let session):
                                        Button {
                                            editingFastingSession = session
                                        } label: {
                                            if session.isActive {
                                                ActiveFastingRow(session: session)
                                            } else {
                                                CompletedFastingRow(session: session)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .swipeActions(edge: .trailing, allowsFullSwipe: !session.isActive) {
                                            if session.isActive {
                                                Button {
                                                    endFast()
                                                } label: {
                                                    Label("End Fast", systemImage: "stop.fill")
                                                }
                                                .tint(AppColors.calorie)
                                                Button(role: .destructive) {
                                                    fastingStore.cancelActive()
                                                    notificationManager.cancelFastingGoal()
                                                } label: {
                                                    Label("Cancel Fast", systemImage: "trash.fill")
                                                }
                                            } else {
                                                Button {
                                                    pendingDiaryDeletion = .fasting(session)
                                                } label: {
                                                    Label("Delete", systemImage: "trash.fill")
                                                }
                                                .tint(.red)
                                            }
                                        }
                                    }
                                }
                                .listRowBackground(AppColors.appCard)
                            }
                        } header: {
                            HStack(alignment: .center) {
                                Label(group.meal.displayName, systemImage: group.meal.icon)
                                if group.id == mealGroups.first?.id {
                                    Menu {
                                        Picker("Food Log Order", selection: $foodLogSortOrderRaw) {
                                            ForEach(FoodLogSortOrder.allCases) { order in
                                                Text(order.displayName).tag(order.rawValue)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "arrow.up.arrow.down")
                                                .font(.system(.caption2, design: .rounded, weight: .semibold))
                                            Text("Sort")
                                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        }
                                    }
                                    .tint(AppColors.calorie)
                                    .textCase(nil)
                                    .padding(.leading, 8)
                                }
                                Spacer()
                                if !group.foodEntries.isEmpty {
                                    // Share and totals include food only; water and fasting have no calories/macros.
                                    Button {
                                        MealShare.presentShareSheet(for: group.foodEntries)
                                    } label: {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                            .foregroundStyle(AppColors.calorie)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.trailing, 12)
                                    .textCase(nil)
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("\(group.totalCalories.formatted()) kcal")
                                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                            .foregroundStyle(AppColors.calorie)
                                        Text("\(Int(group.totalProtein.rounded()))P · \(Int(group.totalCarbs.rounded()))C · \(Int(group.totalFat.rounded()))F")
                                            .font(.system(.caption2, design: .rounded, weight: .medium))
                                            .foregroundStyle(.secondary)
                                    }
                                    .textCase(nil)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.appBackground)
            .animation(IronTheme.motion, value: selectedDate)
            .contentMargins(.bottom, isFoodSelectionMode ? 8 : 96, for: .scrollContent)
            .sensoryFeedback(.selection, trigger: selectedFoodIDs) { _, selection in
                !selection.isEmpty
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isFoodSelectionMode {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            foodSelectionSummary
                            combineFoodButton
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            foodSelectionSummary
                            combineFoodButton
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(IronTheme.surface, in: RoundedRectangle(cornerRadius: IronTheme.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: IronTheme.cardRadius, style: .continuous)
                            .strokeBorder(IronTheme.hairline, lineWidth: 1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppColors.appBackground)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(IronTheme.heavyHeadline)
                        .fontWidth(.condensed)
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundStyle(IronTheme.textPrimary)
                        .monospacedDigit()
                        // Capped at AX2 so a scaled principal title cannot crowd the bar buttons.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
            }
    }

    private var homeAddOverlay: some View {
        homeDiaryList
            .overlay(alignment: .bottomTrailing) {
                Menu {
                    if fastingTrackingEnabled {
                        Section {
                            if fastingStore.activeSession != nil {
                                Menu {
                                    Button {
                                        endFast()
                                    } label: {
                                        Label("End Fast", systemImage: "stop.fill")
                                    }
                                    Button(role: .destructive) {
                                        fastingStore.cancelActive()
                                        notificationManager.cancelFastingGoal()
                                    } label: {
                                        Label("Cancel Fast", systemImage: "trash")
                                    }
                                } label: {
                                    Label("Fasting", systemImage: "timer")
                                }
                            } else {
                                Button {
                                    presentFoodDestination {
                                        showFastingStart = true
                                    }
                                } label: {
                                    Label("Start Fast", systemImage: "timer")
                                }
                            }
                        }
                    }
                    if waterTrackingEnabled {
                        Section {
                            Menu {
                                waterQuickMenuItems
                            } label: {
                                Label("Water", systemImage: "drop.fill")
                            }
                        }
                    }
                    if fastingStore.activeSession == nil {
                        configuredFoodAddMenuContent
                    }
                } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 60, height: 60)
                                .background(AppColors.calorie, in: Circle())
                        }
                        .accessibilityIdentifier("home.add")
                        .opacity(isFoodSelectionMode ? 0 : 1)
                        .disabled(isFoodSelectionMode)
                        .allowsHitTesting(!isFoodSelectionMode)
                        .popover(isPresented: $showTextPopover) {
                            TextFoodInputView(
                                onCancel: {
                                    showTextPopover = false
                                },
                                onSubmit: { description in
                                    showTextPopover = false
                                    currentImage = nil
                                    currentImages = []
                                    currentEmoji = nil
                                    currentFoodSource = .textInput
                                    startTextAnalysis(description)
                                }
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                        .popover(isPresented: $showVoicePopover) {
                            VoiceInputView(
                                onCancel: {
                                    showVoicePopover = false
                                },
                                onSubmit: { description in
                                    showVoicePopover = false
                                    currentImage = nil
                                    currentImages = []
                                    currentEmoji = nil
                                    currentFoodSource = .textInput
                                    startTextAnalysis(description)
                                }
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                        .popover(isPresented: $showManualPopover) {
                            ManualEntryView(
                                logDate: logDateForSelectedDay,
                                onCancel: { showManualPopover = false },
                                onSave: { entry in
                                    showManualPopover = false
                                    if !foodStore.addEntry(entry) { showFoodLoggingBlocked = true }
                                }
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                        .padding(24)
            }
    }

    private var homeCoveredDiary: some View {
        homeAddOverlay
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(
                    image: $capturedImage,
                    title: captureImages.isEmpty ? nil : "Photo \(captureImages.count + 1)",
                    onCancel: {
                        if !captureImages.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                showMultiPhotoCaptureSheet = true
                            }
                        }
                    }
                )
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showBarcodeScanner) {
                BarcodeScannerView(
                    onScan: { barcode in
                        showBarcodeScanner = false
                        startBarcodeLookup(barcode)
                    },
                    onCancel: {
                        showBarcodeScanner = false
                    }
                )
                .ignoresSafeArea()
            }
            .onChange(of: capturedImage) { oldValue, newValue in
                guard let image = newValue else { return }
                capturedImage = nil
                currentEmoji = nil

                captureImages.append(image)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    showMultiPhotoCaptureSheet = true
                }
            }
            .sheet(isPresented: $showMultiPhotoCaptureSheet) {
                MultiPhotoCaptureSheet(
                    images: $captureImages,
                    isImportingPhotos: isImportingPhotos,
                    selectedPhotoItems: $selectedPhotoItems,
                    description: $contextDescription,
                    onAddPhoto: {
                        guard captureImages.count < 10 else { return }
                        showMultiPhotoCaptureSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            showCamera = true
                        }
                    },
                    onRemove: { index in
                        guard captureImages.indices.contains(index) else { return }
                        captureImages.remove(at: index)
                        if captureImages.isEmpty {
                            showMultiPhotoCaptureSheet = false
                        }
                    },
                    onAnalyze: { progressiveMeal in
                        let images = captureImages
                        let description = cameraMode == .snapFoodWithContext ? contextDescription : nil
                        showMultiPhotoCaptureSheet = false
                        captureImages = []
                        currentImages = images
                        currentImage = images.first
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            startAnalysis(
                                images: images,
                                mode: cameraMode,
                                description: description,
                                progressiveMeal: progressiveMeal
                            )
                        }
                    },
                    onCancel: {
                        showMultiPhotoCaptureSheet = false
                        captureImages = []
                        contextDescription = ""
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showContextSheet) {
                ContextDescriptionSheet(
                    image: pendingContextImage,
                    description: $contextDescription,
                    onAnalyze: {
                        let desc = contextDescription
                        let image = pendingContextImage
                        showContextSheet = false
                        pendingContextImage = nil
                        
                        if let image {
                            // Delay presenting the next sheet until the current one fully dismisses.
                            // This prevents SwiftUI from silently ignoring the new activeSheet presentation.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                currentImage = image // Ensure currentImage is set so AnalyzingView/FoodResultView shows the image
                                currentImages = [image]
                                startAnalysis(image: image, mode: .snapFoodWithContext, description: desc)
                            }
                        }
                    },
                    onCancel: {
                        showContextSheet = false
                        pendingContextImage = nil
                        currentImage = nil
                        currentImages = []
                    }
                )
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .analyzing, .analyzingText, .lookingUpBarcode, .foodResult:
                    // Drive content from foodLogPhase, not the captured `sheet`
                    // value — `.sheet(item:)` will not recreate the body when
                    // identity stays `foodLog`.
                    Group {
                    switch foodLogPhase {
                    case .analyzing:
                        AnalyzingView(image: currentImage, onCancel: cancelAnalysis)
                    case .analyzingText:
                        AnalyzingView(image: nil, message: "Looking up nutrition...", onCancel: cancelAnalysis)
                    case .lookingUpBarcode:
                        AnalyzingView(image: nil, message: "Looking up barcode...", onCancel: cancelAnalysis)
                    case .result:
                    if let result = currentFoodResult {
                        FoodResultView(
                            images: currentImages,
                            emoji: currentEmoji,
                            source: currentFoodSource,
                            name: result.name,
                            calories: result.calories,
                            protein: result.protein,
                            carbs: result.carbs,
                            fat: result.fat,
                            ingredients: result.ingredients,
                            progressiveMeal: result.progressiveMeal,
                            productMetadata: result.productMetadata,
                            servingSizeGrams: result.servingSizeGrams,
                            sugar: result.sugar,
                            addedSugar: result.addedSugar,
                            fiber: result.fiber,
                            saturatedFat: result.saturatedFat,
                            monounsaturatedFat: result.monounsaturatedFat,
                            polyunsaturatedFat: result.polyunsaturatedFat,
                            cholesterol: result.cholesterol,
                            caffeine: result.caffeine,
                            supplementalNutrients: result.supplementalNutrients,
                            sodium: result.sodium,
                            potassium: result.potassium,
                            transFat: result.transFat,
                            calcium: result.calcium,
                            iron: result.iron,
                            magnesium: result.magnesium,
                            zinc: result.zinc,
                            vitaminA: result.vitaminA,
                            vitaminC: result.vitaminC,
                            vitaminD: result.vitaminD,
                            vitaminB12: result.vitaminB12,
                            vitaminE: result.vitaminE,
                            vitaminK: result.vitaminK,
                            folate: result.folate,
                            omega3: result.omega3,
                            servingUnitOptions: result.servingUnitOptions,
                            selectedServingUnit: result.selectedServingUnit,
                            selectedServingQuantity: result.selectedServingQuantity,
                            servingSizeIsKnown: result.servingSizeIsKnown,
                            logDate: logDateForSelectedDay,
                            profile: userProfile,
                            entriesForDate: { foodStore.entries(for: $0) },
                            weightMetric: weightUnitRaw == "kg",
                            onLog: { entry in
                                if savedMatchContext != nil {
                                    let preview = savedMatchContext?.entryName ?? entry.name
                                    Task { await JevRouter.shared.report(.mealMatch, .loggedAfterMatch, preview: preview) }
                                }
                                if !foodStore.addEntry(entry) { showFoodLoggingBlocked = true }
                            },
                            estimateCheck: estimateCheckMode(for: result),
                            onReestimate: reestimateUsed ? nil : { direction in
                                reestimateFood(direction: direction, calories: result.calories, name: result.name)
                            },
                            savedMatch: savedMatchContext.map { SavedMatchBanner(entryName: $0.entryName) },
                            onEstimateInstead: savedMatchContext.map { context in
                                {
                                    let original = context.originalDescription
                                    Task { await JevRouter.shared.report(.mealMatch, .userOverride, preview: original) }
                                    currentFoodSource = .textInput
                                    startTextAnalysis(original, bypassSavedMatch: true)
                                }
                            }
                        )
                    }
                    }
                    }
                    .id(foodLogPhase)
                case .editFood:
                    if let editingEntry {
                        EditFoodEntryView(entry: editingEntry)
                    }
                case .importSharedMeal:
                    ImportSharedMealView(meals: pendingSharedMeals) { meals in
                        let logDate = logDateForSelectedDay
                        for meal in meals {
                            if !foodStore.addEntry(meal.duplicatedForLogging(at: logDate, mealType: meal.mealType)) {
                                showFoodLoggingBlocked = true
                                break
                            }
                        }
                        activeSheet = nil
                    } onCancel: {
                        activeSheet = nil
                    }
                }
            }
            .sheet(item: $savedMealsMode, content: { mode in
                RecentsView(mode: mode, logDate: logDateForSelectedDay, onReview: { entry in
                    lastEstimateRequest = nil
                    currentImages = entry.allImageData.compactMap(UIImage.init(data:))
                    currentImage = currentImages.first
                    currentEmoji = entry.emoji
                    currentFoodSource = entry.source
                    savedMatchContext = nil
                    currentFoodResult = GeminiService.FoodAnalysis(savedEntry: entry)
                    foodLogPhase = .result
                    activeSheet = .foodResult
                })
            })
            .sheet(isPresented: $showCopyFromDaySheet) {
                CopyFromDaySheet(targetDate: selectedDate)
            }
            .sheet(isPresented: $showFastingStart) {
                FastingStartSheet(defaultGoalMinutes: fastingDefaultGoalMinutes) { goalMinutes in
                    startFast(goalMinutes: goalMinutes)
                }
            }
            .sheet(item: $editingFastingSession) { session in
                FastingSessionEditorView(
                    session: session,
                    onSave: { updated in
                        let saved = fastingStore.update(updated)
                        if saved { refreshFastingGoalNotification() }
                        return saved
                    },
                    onEndNow: { updated in
                        guard fastingStore.update(updated) else { return false }
                        return endFast()
                    },
                    onDelete: { removed in
                        fastingStore.delete(id: removed.id)
                        refreshFastingGoalNotification()
                    }
                )
            }
            .sheet(isPresented: $showSiriPhrases) {
                NavigationStack {
                    SiriPhrasesSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    showSiriPhrases = false
                                }
                            }
                        }
                }
            }
    }


    @MainActor
    private func presentQuickActionIfPossible() {
        guard let request = quickActionRequest, activeSheet == nil else { return }

        let hadOpenDestination = showCamera || showBarcodeScanner || showPhotoPicker
            || showVoicePopover || showTextPopover || showManualPopover
            || savedMealsMode != nil || showContextSheet || showMultiPhotoCaptureSheet
            || showFastingStart || editingFastingSession != nil

        showCamera = false
        showBarcodeScanner = false
        showPhotoPicker = false
        showVoicePopover = false
        showTextPopover = false
        showManualPopover = false
        savedMealsMode = nil
        showContextSheet = false
        showMultiPhotoCaptureSheet = false
        showCopyFromDaySheet = false
        showNutritionDetail = false
        showCustomWaterLog = false
        showError = false
        showFastingStart = false
        editingFastingSession = nil
        selectedDate = .now

        if request.action == .fasting {
            onQuickActionHandled(request.id)
            let launchFasting: @MainActor @Sendable () -> Void = {
                if !fastingTrackingEnabled {
                    showFastingQuickActionDisabled = true
                } else if let active = fastingStore.activeSession {
                    editingFastingSession = active
                } else {
                    showFastingStart = true
                }
            }
            if hadOpenDestination {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: launchFasting)
            } else {
                launchFasting()
            }
            return
        }

        guard fastingStore.activeSession == nil else {
            onQuickActionHandled(request.id)
            showFoodLoggingBlocked = true
            return
        }

        onQuickActionHandled(request.id)
        let launch: @MainActor @Sendable () -> Void = {
            presentFoodDestination {
                switch request.action {
                case .camera:
                    cameraMode = .snapFoodWithContext
                    isImportingPhotos = false
                    captureImages = []
                    contextDescription = ""
                    showCamera = true
                case .photos:
                    cameraMode = .snapFoodWithContext
                    isImportingPhotos = true
                    captureImages = []
                    contextDescription = ""
                    selectedPhotoItems = []
                    showPhotoPicker = true
                case .voice:
                    showVoicePopover = true
                case .text:
                    showTextPopover = true
                case .barcode:
                    showBarcodeScanner = true
                case .favorites:
                    savedMealsMode = .favorites
                case .frequent:
                    savedMealsMode = .frequent
                case .recent:
                    savedMealsMode = .recent
                case .manual:
                    showManualPopover = true
                case .fasting:
                    break
                }
            }
        }

        if hadOpenDestination {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: launch)
        } else {
            launch()
        }
    }

    @MainActor
    private func presentFoodLogMethodIfPossible() {
        guard let request = foodLogMethodRequest, activeSheet == nil else { return }

        let hadOpenDestination = showCamera || showBarcodeScanner || showPhotoPicker
            || showVoicePopover || showTextPopover || showManualPopover
            || savedMealsMode != nil || showContextSheet || showMultiPhotoCaptureSheet
            || showCopyFromDaySheet || showFastingStart || editingFastingSession != nil

        showCamera = false
        showBarcodeScanner = false
        showPhotoPicker = false
        showVoicePopover = false
        showTextPopover = false
        showManualPopover = false
        savedMealsMode = nil
        showContextSheet = false
        showMultiPhotoCaptureSheet = false
        showCopyFromDaySheet = false
        showNutritionDetail = false
        showCustomWaterLog = false
        showError = false
        showFastingStart = false
        editingFastingSession = nil
        selectedDate = .now

        guard fastingStore.activeSession == nil else {
            onFoodLogMethodHandled(request.id)
            showFoodLoggingBlocked = true
            return
        }

        onFoodLogMethodHandled(request.id)
        let launch: @MainActor @Sendable () -> Void = {
            presentFoodDestination {
                performFoodLogMethod(request.method)
            }
        }

        if hadOpenDestination {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: launch)
        } else {
            launch()
        }
    }
    
    private func checkAndConsumeSharedImage() {
        guard ShareImportManager.hasSharedImage() else { return }
        guard canBeginFoodLogging() else { return }
        guard let image = ShareImportManager.consumeSharedImage() else { return }
        
        // Force dismiss any currently open sheets to prevent SwiftUI from swallowing the new presentation
        activeSheet = nil
        
        currentImage = image
        currentImages = [image]
        currentEmoji = nil
        currentFoodSource = .snapFood

        // A slight delay ensures the view hierarchy is clear before presenting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pendingContextImage = image
            contextDescription = ""
            showContextSheet = true
        }
    }

    private func startAnalysis(image: UIImage, mode: CameraMode, description: String? = nil) {
        startAnalysis(images: [image], mode: mode, description: description, progressiveMeal: false)
    }

    private func startAnalysis(
        images: [UIImage],
        mode: CameraMode,
        description: String? = nil,
        progressiveMeal: Bool = false,
        isReestimate: Bool = false
    ) {
        let request = RetryRequest.analysis(
            images: images,
            mode: mode,
            description: description,
            progressiveMeal: progressiveMeal
        )
        retryRequest = request
        lastEstimateRequest = request
        reestimateUsed = isReestimate
        presentFoodLogLoading(.analyzing)

        analysisTask?.cancel()
        analysisTask = Task {
            do {
                switch mode {
                case .snapFood:
                    let result = try await GeminiService.analyzeFood(
                        images: images,
                        progressiveMeal: progressiveMeal
                    )
                    try Task.checkCancellation()
                    currentFoodSource = .snapFood
                    retryRequest = nil
                    presentFoodResult(result)

                case .snapFoodWithContext:
                    let result = try await GeminiService.analyzeFood(
                        images: images,
                        description: description,
                        progressiveMeal: progressiveMeal
                    )
                    try Task.checkCancellation()
                    currentFoodSource = .snapFood
                    retryRequest = nil
                    presentFoodResult(result)

                }
            } catch is CancellationError {
                // User tapped Cancel on the analyzing sheet; cancelAnalysis already reset the UI.
            } catch {
                if Task.isCancelled { return }
                presentAnalysisError(error)
            }
        }
    }

    /// Cancel button on the analyzing sheet. Cancels the task (which also cancels the underlying
    /// URLSession request), dismisses the sheet, and drops the retry request so no error alert follows.
    private func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        retryRequest = nil
        if foodLogPhase.isLoading {
            activeSheet = nil
        }
        foodLogPhase = .result
    }

    @MainActor
    private func presentFoodLogLoading(_ phase: FoodLogPhase) {
        currentFoodResult = nil
        foodLogPhase = phase
        switch phase {
        case .analyzing:
            activeSheet = .analyzing
        case .analyzingText:
            activeSheet = .analyzingText
        case .lookingUpBarcode:
            activeSheet = .lookingUpBarcode
        case .result:
            activeSheet = .foodResult
        }
    }

    @MainActor
    private func presentFoodResult(_ result: GeminiService.FoodAnalysis) {
        currentFoodResult = result
        foodLogPhase = .result
        activeSheet = .foodResult
    }

    private func estimateCheckMode(for result: GeminiService.FoodAnalysis) -> EstimateCheckMode {
        if savedMatchContext != nil { return .off }
        guard TypeSafeSettings.isConfigured else { return .off }
        let name = result.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.calories > 0, !name.isEmpty else { return .off }
        let allowed = currentFoodSource == .snapFood
            || (currentFoodSource == .textInput && TypeSafeSettings.checkTypedMeals)
        guard allowed else { return .off }
        return .live(EstimateCheckInput(analysis: result, userNote: estimateUserNote))
    }

    private var estimateUserNote: String? {
        switch lastEstimateRequest {
        case .analysis(_, _, let description, _):
            return description
        case .text(let description):
            return description
        default:
            return nil
        }
    }

    private func reestimateFood(direction: EstimateDirection, calories: Int, name: String) {
        guard !reestimateUsed, let lastEstimateRequest else { return }
        Task { await JevRouter.shared.report(.estimateCheck, .userOverride, preview: name) }
        let hint = "A plausibility check flagged the previous estimate (\(calories) kcal for \(name)) as likely too \(direction.phrase). Re-check portion size and calorie density carefully."
        switch lastEstimateRequest {
        case .analysis(let images, _, let description, let progressiveMeal):
            startAnalysis(
                images: images,
                mode: .snapFoodWithContext,
                description: (description ?? "") + hint,
                progressiveMeal: progressiveMeal,
                isReestimate: true
            )
        case .text(let description):
            currentFoodSource = .textInput
            startTextAnalysis(description + "\n" + hint, isReestimate: true)
        case .barcode:
            break
        }
    }

    private func startBarcodeLookup(_ barcode: String) {
        let trimmedBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBarcode.isEmpty else { return }
        retryRequest = .barcode(trimmedBarcode)

        currentImage = nil
        currentImages = []
        currentEmoji = nil
        currentFoodSource = .barcode
        presentFoodLogLoading(.lookingUpBarcode)

        analysisTask?.cancel()
        analysisTask = Task {
            do {
                let lookup = try await OpenFoodFactsService.lookupWithImage(barcode: trimmedBarcode)
                try Task.checkCancellation()
                let result = lookup.analysis
                currentEmoji = result.emoji
                if let imageData = lookup.productImageData,
                   let image = UIImage(data: imageData) {
                    currentImage = image
                    currentImages = [image]
                }
                retryRequest = nil
                presentFoodResult(result)
            } catch is CancellationError {
                // User tapped Cancel on the analyzing sheet; cancelAnalysis already reset the UI.
            } catch {
                if Task.isCancelled { return }
                presentBarcodeLookupError(error)
            }
        }
    }

    private func startTextAnalysis(_ description: String, isReestimate: Bool = false, bypassSavedMatch: Bool = false) {
        let request = RetryRequest.text(description)
        retryRequest = request
        lastEstimateRequest = request
        reestimateUsed = isReestimate
        savedMatchContext = nil
        presentFoodLogLoading(.analyzingText)
        analysisTask?.cancel()
        analysisTask = Task {
            if !bypassSavedMatch, !isReestimate,
               let entry = await SavedMealMatcher.match(description, store: foodStore) {
                if Task.isCancelled { return }
                presentSavedMatch(entry, description: description)
                return
            }
            do {
                let result = try await GeminiService.analyzeTextInput(description: description)
                try Task.checkCancellation()
                currentEmoji = result.emoji
                retryRequest = nil
                presentFoodResult(result)
            } catch is CancellationError {
                // User tapped Cancel on the analyzing sheet; cancelAnalysis already reset the UI.
            } catch {
                if Task.isCancelled { return }
                presentAnalysisError(error)
            }
        }
    }

    @MainActor
    private func presentSavedMatch(_ entry: FoodEntry, description: String) {
        lastEstimateRequest = .text(description)
        currentImage = nil
        currentImages = []
        currentEmoji = entry.emoji
        currentFoodSource = entry.source
        retryRequest = nil
        savedMatchContext = SavedMatchContext(entryName: entry.name, originalDescription: description)
        presentFoodResult(GeminiService.FoodAnalysis(savedEntry: entry))
    }

    private func consumeRouterFoodHandoff() {
        guard let text = routerHandoff.pendingFoodText else { return }
        routerHandoff.pendingFoodText = nil
        guard canBeginFoodLogging() else { return }
        currentFoodSource = .textInput
        startTextAnalysis(text)
    }

    /// Dismiss the loading sheet first, then present the alert after the sheet
    /// animation finishes. Presenting both in the same turn makes SwiftUI flash
    /// or drop the alert.
    @MainActor
    private func presentAnalysisError(_ error: Error) {
        foodLogPhase = .result
        activeSheet = nil
        if let quotaError = error as? HostedAIQuotaError {
            switch quotaError {
            case .quotaExceeded:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    showHostedQuotaPaywall = true
                }
                return
            case .noActiveSubscription:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    showHostedPaywall = true
                }
                return
            case .notHostedMode, .rateLimited:
                break
            }
        }
        errorMessage = GeminiService.analysisErrorMessage(error)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            showError = true
        }
    }

    @MainActor
    private func presentBarcodeLookupError(_ error: Error) {
        let offersScanLabel: Bool
        if let lookupError = error as? OpenFoodFactsService.LookupError {
            switch lookupError {
            case .missingNutrition, .productNotFound:
                offersScanLabel = true
            default:
                offersScanLabel = false
            }
        } else {
            offersScanLabel = false
        }

        let message = (error as? OpenFoodFactsService.LookupError)?.localizedDescription
            ?? OpenFoodFactsService.LookupError.invalidResponse.localizedDescription
        errorMessage = message
        // End the loading sheet first, then show only the system popup.
        foodLogPhase = .result
        activeSheet = nil
        BarcodeLookupAlertPresenter.present(
            message: message,
            offersScanLabel: offersScanLabel
        )
    }

    @MainActor
    private func openCameraForNutritionLabel() {
        guard canBeginFoodLogging() else { return }
        cameraMode = .snapFoodWithContext
        isImportingPhotos = false
        captureImages = []
        contextDescription = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showCamera = true
        }
    }

    private func retryLastRequest() {
        guard let retryRequest else { return }
        switch retryRequest {
        case let .analysis(images, mode, description, progressiveMeal):
            startAnalysis(
                images: images,
                mode: mode,
                description: description,
                progressiveMeal: progressiveMeal
            )
        case let .text(description):
            startTextAnalysis(description)
        case let .barcode(barcode):
            startBarcodeLookup(barcode)
        }
    }

}

// Configurable + menu helpers (same file as HomeView so private state is accessible).
extension HomeView {
    @ViewBuilder
    var configuredFoodAddMenuContent: some View {
        let config = AddMenuSettings.load()
        if config.usesFlatLayout {
            Section {
                ForEach(config.flatMethods.filter { $0 != .siriPhrases }) { method in
                    addMenuButton(for: method)
                }
            }
        } else {
            ForEach(config.groups.filter { !$0.methods.isEmpty }) { group in
                Section {
                    Menu {
                        ForEach(group.methods.filter { $0 != .siriPhrases }) { method in
                            addMenuButton(for: method)
                        }
                    } label: {
                        Label(group.name, systemImage: addMenuGroupIcon(for: group))
                    }
                }
            }
        }
    }

    @ViewBuilder
    func addMenuButton(for method: FoodLogMethod) -> some View {
        Button {
            presentFoodDestination {
                performFoodLogMethod(method)
            }
        } label: {
            Label(method.title, systemImage: method.systemImageName)
        }
    }

    func performFoodLogMethod(_ method: FoodLogMethod) {
        switch method {
        case .camera:
            cameraMode = .snapFoodWithContext
            isImportingPhotos = false
            captureImages = []
            contextDescription = ""
            showCamera = true
        case .photos:
            cameraMode = .snapFoodWithContext
            isImportingPhotos = true
            captureImages = []
            contextDescription = ""
            selectedPhotoItems = []
            showPhotoPicker = true
        case .barcode:
            showBarcodeScanner = true
        case .voice:
            showVoicePopover = true
        case .text:
            showTextPopover = true
        case .manual:
            showManualPopover = true
        case .siriPhrases:
            showSiriPhrases = true
        case .favorites:
            savedMealsMode = .favorites
        case .frequent:
            savedMealsMode = .frequent
        case .recent:
            savedMealsMode = .recent
        case .copyFromDay:
            showCopyFromDaySheet = true
        }
    }

    private func addMenuGroupIcon(for group: AddMenuGroupConfig) -> String {
        group.methods.first?.systemImageName ?? "folder.fill"
    }
}

private extension Notification.Name {
    static let fudBarcodeAlertScanLabel = Notification.Name("fudBarcodeAlertScanLabel")
    static let fudBarcodeAlertRetry = Notification.Name("fudBarcodeAlertRetry")
    static let fudBarcodeAlertCancel = Notification.Name("fudBarcodeAlertCancel")
}

/// UIKit alert so the barcode error popup survives SwiftUI sheet dismissal.
@MainActor
private enum BarcodeLookupAlertPresenter {
    static func present(message: String, offersScanLabel: Bool, attempt: Int = 0) {
        guard let root = keyRootViewController() else { return }

        // Wait until the "Looking up barcode..." sheet has fully dismissed.
        if root.presentedViewController != nil, attempt < 30 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                present(message: message, offersScanLabel: offersScanLabel, attempt: attempt + 1)
            }
            return
        }

        let alert = UIAlertController(
            title: "Couldn't use this barcode",
            message: message,
            preferredStyle: .alert
        )
        if offersScanLabel {
            alert.addAction(UIAlertAction(title: "Scan Label", style: .default) { _ in
                NotificationCenter.default.post(name: .fudBarcodeAlertScanLabel, object: nil)
            })
        } else {
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                NotificationCenter.default.post(name: .fudBarcodeAlertRetry, object: nil)
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            NotificationCenter.default.post(name: .fudBarcodeAlertCancel, object: nil)
        })
        root.present(alert, animated: true)
    }

    private static func keyRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
