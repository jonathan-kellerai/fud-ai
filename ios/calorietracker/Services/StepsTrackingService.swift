//
//  StepsTrackingService.swift
//  calorietracker
//
//  Daily steps tracking via HealthKit + Neon bridge sync
//

import Foundation
import HealthKit
import BackgroundTasks

@Observable
final class StepsTrackingService {
    static let shared = StepsTrackingService()
    
    var todaySteps: Int = 0
    var yesterdaySteps: Int = 0
    var last7Days: [StepsDay] = []
    var lastSyncDate: Date?
    var lastSyncError: String?
    var isSyncing = false
    
    /// Set by the app so Sync Now, steps refresh, and the background task also import weight.
    static var onBodyMeasurementsSync: (() async -> Void)?

    private let healthStore = HKHealthStore()
    private let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
    private let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)!
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return cal
    }()
    private var observerQuery: HKObserverQuery?
    
    private init() {}
    
    // MARK: - HealthKit Authorization
    
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "StepsTracking", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "HealthKit is not available on this device"
            ])
        }
        
        try await healthStore.requestAuthorization(
            toShare: [],
            read: [stepsType, bodyMassType, bodyFatType]
        )
    }
    
    // MARK: - Steps Reading
    
    func fetchTodaySteps() async throws -> Int {
        let steps = try await fetchSteps(for: startOfToday())
        todaySteps = steps
        return steps
    }
    
    func fetchYesterdaySteps() async throws -> Int {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday())!
        let steps = try await fetchSteps(for: yesterday)
        yesterdaySteps = steps
        return steps
    }
    
    func fetchLast7Days() async throws -> [StepsDay] {
        var days: [StepsDay] = []
        let today = startOfToday()
        
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            let steps = try await fetchSteps(for: date)
            let dateString = formatDate(date)
            
            days.append(StepsDay(
                date: dateString,
                steps: steps,
                met: steps >= 10000,
                logged: steps > 0,
                source: "Apple Health",
                device: "Apple Health",
                origin: "jl-fud-native-healthkit"
            ))
        }
        
        last7Days = days
        return days
    }
    
    private func fetchSteps(for date: Date) async throws -> Int {
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Background Observation
    
    func enableBackgroundDelivery() {
        healthStore.enableBackgroundDelivery(for: stepsType, frequency: .hourly) { success, error in
            if let error = error {
                print("Failed to enable background delivery: \(error)")
            }
        }
        
        // Set up observer query
        let query = HKObserverQuery(sampleType: stepsType, predicate: nil) { [weak self] _, completionHandler, error in
            if let error = error {
                print("Observer query error: \(error)")
                completionHandler()
                return
            }
            
            Task {
                try? await self?.syncStepsToBackend()
                completionHandler()
            }
        }
        
        observerQuery = query
        healthStore.execute(query)
    }
    
    func disableBackgroundDelivery() {
        if let query = observerQuery {
            healthStore.stop(query)
            observerQuery = nil
        }
        
        healthStore.disableAllBackgroundDelivery { success, error in
            if let error = error {
                print("Failed to disable background delivery: \(error)")
            }
        }
    }
    
    // MARK: - Sync to Backend
    
    func syncStepsToBackend() async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        
        // Fetch today and yesterday
        let today = try await fetchTodaySteps()
        let yesterday = try await fetchYesterdaySteps()
        
        let bridge = NeonBridgeService.shared
        
        // Post today's steps
        if today > 0 {
            let todayPayload = StepsPayload(
                date: formatDate(startOfToday()),
                steps: today,
                device: "Apple Health",
                source: "jl-fud-native-healthkit"
            )
            _ = try await bridge.postSteps(todayPayload)
        }
        
        // Post yesterday's final total
        if yesterday > 0 {
            let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: startOfToday())!
            let yesterdayPayload = StepsPayload(
                date: formatDate(yesterdayDate),
                steps: yesterday,
                device: "Apple Health",
                source: "jl-fud-native-healthkit"
            )
            _ = try await bridge.postSteps(yesterdayPayload)
        }
        
        lastSyncDate = Date()
        lastSyncError = nil
        await Self.syncBodyMeasurementsFromHealth()
    }
    
    func syncStepsInBackground() async {
        do {
            try await syncStepsToBackend()
        } catch {
            lastSyncError = error.localizedDescription
            print("Background steps sync failed: \(error)")
            await Self.syncBodyMeasurementsFromHealth()
        }
    }

    static func syncBodyMeasurementsFromHealth() async {
        if let onBodyMeasurementsSync {
            await onBodyMeasurementsSync()
            return
        }
        await HealthKitManager.importBodyMeasurementsIntoTemporaryStores()
    }
    
    // MARK: - Background Task Registration
    
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.jlphysical.steps-sync",
            using: nil
        ) { task in
            Task {
                await StepsTrackingService.shared.syncStepsInBackground()
                task.setTaskCompleted(success: true)
            }
            
            scheduleBackgroundTask()
        }
    }
    
    static func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: "com.jlphysical.steps-sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600) // 1 hour from now
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func startOfToday() -> Date {
        calendar.startOfDay(for: Date())
    }
    
    private func formatDate(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
