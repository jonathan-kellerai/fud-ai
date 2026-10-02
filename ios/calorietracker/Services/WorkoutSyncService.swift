//
//  WorkoutSyncService.swift
//  calorietracker
//
//  Sync StrengthWorkoutSession to Neon bridge as WorkoutPayload
//

import Foundation

@Observable
final class WorkoutSyncService {
    static let shared = WorkoutSyncService()
    
    var syncQueue: [UUID] = []
    var lastSyncError: String?
    var isSyncing = false
    
    private let bridge = NeonBridgeService.shared
    private let queueKey = "workoutSyncQueue"
    
    private init() {
        loadQueue()
    }
    
    // MARK: - Queue Management
    
    private func loadQueue() {
        if let data = UserDefaults.standard.data(forKey: queueKey),
           let queue = try? JSONDecoder().decode([UUID].self, from: data) {
            syncQueue = queue
        }
    }
    
    private func saveQueue() {
        if let data = try? JSONEncoder().encode(syncQueue) {
            UserDefaults.standard.set(data, forKey: queueKey)
        }
    }
    
    func addToQueue(sessionID: UUID) {
        if !syncQueue.contains(sessionID) {
            syncQueue.append(sessionID)
            saveQueue()
        }
    }
    
    func removeFromQueue(sessionID: UUID) {
        syncQueue.removeAll { $0 == sessionID }
        saveQueue()
    }
    
    // MARK: - Sync
    
    func syncSession(_ session: StrengthWorkoutSession, programDay: String? = nil) async throws -> WorkoutResponse {
        let payload = convertToPayload(session, programDay: programDay)
        let response = try await bridge.postWorkout(payload)
        
        if response.deduped == true {
            // Server already has this workout, no need to retry
            removeFromQueue(sessionID: session.id)
        } else if response.ok == true {
            // Successfully synced
            removeFromQueue(sessionID: session.id)
        }
        
        return response
    }
    
    func processQueue(with sessions: [StrengthWorkoutSession]) async {
        guard !isSyncing else { return }
        guard !syncQueue.isEmpty else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        for sessionID in syncQueue {
            guard let session = sessions.first(where: { $0.id == sessionID }) else {
                // Session not found, remove from queue
                removeFromQueue(sessionID: sessionID)
                continue
            }
            
            do {
                _ = try await syncSession(session)
            } catch {
                lastSyncError = error.localizedDescription
                print("Failed to sync session \(sessionID): \(error)")
                // Keep in queue for retry
            }
        }
    }
    
    // MARK: - Delete
    
    func deleteWorkout(id: String) async throws {
        try await bridge.deleteWorkout(id: id)
    }
    
    // MARK: - Conversion
    
    private func convertToPayload(_ session: StrengthWorkoutSession, programDay: String?) -> WorkoutPayload {
        let sets = session.exercises.enumerated().flatMap { exerciseIndex, exercise in
            exercise.sets.enumerated().compactMap { setIndex, set -> WorkoutSet? in
                guard set.isPerformed else { return nil }
                
                let reps = Int(set.reps) ?? 0
                guard reps > 0 else { return nil }
                
                let load = Double(set.weight.replacingOccurrences(of: ",", with: ".")) ?? 0
                let rir = set.rpeScale != nil ? extractRIR(from: set.rpe, scale: set.rpeScale!) : nil
                let rpe = set.rpeScale != nil ? extractRPE(from: set.rpe, scale: set.rpeScale!) : nil
                
                return WorkoutSet(
                    exercise: exercise.name.lowercased(),
                    load: load,
                    reps: reps,
                    rir: rir,
                    rpe: rpe,
                    order: exerciseIndex * 100 + setIndex + 1
                )
            }
        }
        
        // Try to extract conditioning info from session notes if available
        let conditioning: String? = nil // TODO: Extract from session if stored
        
        // Determine program day from title or use provided
        let detectedProgramDay = programDay ?? detectProgramDay(from: session)
        
        return WorkoutPayload(
            kind: "COMPLETED",
            programVersion: "program-v2",
            programDay: detectedProgramDay,
            title: extractTitle(from: detectedProgramDay),
            units: session.exercises.first?.sets.first?.weightUnit ?? "lb",
            sessionDate: formatSessionDate(session.diaryDate),
            conditioning: conditioning,
            notes: [],
            recordedAtUtc: formatISO8601(session.completedAt),
            openedAtUtc: formatISO8601(session.startedAt),
            source: "jl-fud-native",
            sets: sets
        )
    }
    
    private func detectProgramDay(from session: StrengthWorkoutSession) -> String {
        // Try to match exercises to Program V2 days
        let exerciseNames = Set(session.exercises.map { $0.name.lowercased() })
        
        // Check for key exercises in each program day
        if exerciseNames.contains("leg press") {
            return "Day1_LowerA"
        } else if exerciseNames.contains("chest press machine") {
            return "Day2_UpperPush"
        } else if exerciseNames.contains("cable pull-through") || exerciseNames.contains("chest-supported row") {
            return "Day3_PullHinge"
        } else if exerciseNames.contains("incline chest press") {
            return "Day4_UpperPhysique"
        } else if exerciseNames.contains("hack squat") || exerciseNames.contains("hip thrust") {
            return "Day5_LowerB_Cond"
        }
        
        // Default to generic
        return "Day1_LowerA"
    }
    
    private func extractTitle(from programDay: String) -> String {
        switch programDay {
        case "Day1_LowerA": return "Lower A"
        case "Day2_UpperPush": return "Upper Push"
        case "Day3_PullHinge": return "Pull/Hinge"
        case "Day4_UpperPhysique": return "Upper Physique"
        case "Day5_LowerB_Cond": return "Lower B"
        default: return "Workout"
        }
    }
    
    private func extractRIR(from rpeText: String, scale: StrengthWorkoutRPEScale) -> Int? {
        guard let rpe = Double(rpeText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        
        // Approximate RIR from RPE (this is a rough conversion)
        // For strength scale (1-10): RIR ~= 10 - RPE
        // For CR10 (0-10): RIR ~= 10 - RPE
        // For Borg (6-20): normalize to 0-10 first
        
        switch scale {
        case .strength:
            return max(0, 10 - Int(rpe.rounded()))
        case .cr10:
            return max(0, 10 - Int(rpe.rounded()))
        case .borg:
            let normalized = (rpe - 6) / 14 * 10
            return max(0, 10 - Int(normalized.rounded()))
        }
    }
    
    private func extractRPE(from rpeText: String, scale: StrengthWorkoutRPEScale) -> Double? {
        guard let value = Double(rpeText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return value
    }
    
    private func formatSessionDate(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let components = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
    
    private func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
