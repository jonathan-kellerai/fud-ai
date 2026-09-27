//
//  StepsView.swift
//  calorietracker
//
//  Daily steps tracking view
//

import SwiftUI
import HealthKit

struct StepsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var stepsService = StepsTrackingService.shared
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingPermission = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Today's Progress Card
                    todayCard
                    
                    // 7-Day History
                    weeklyHistory
                    
                    // Sync Status
                    syncStatus
                }
                .padding()
            }
            .navigationTitle("Daily Steps")
            .refreshable {
                await refreshSteps()
            }
            .task {
                await loadInitialData()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await refreshSteps() }
                }
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil }
            } message: {
                if let error {
                    Text(error)
                }
            }
        }
    }
    
    private var todayCard: some View {
        VStack(spacing: 16) {
            Text("Today")
                .font(.headline)
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                    .frame(width: 200, height: 200)
                
                Circle()
                    .trim(from: 0, to: min(Double(stepsService.todaySteps) / 10000.0, 1.0))
                    .stroke(
                        stepsService.todaySteps >= 10000 ? Color.green : Color.blue,
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: stepsService.todaySteps)
                
                VStack {
                    Text("\(stepsService.todaySteps)")
                        .font(.system(size: 48, weight: .bold))
                        .monospacedDigit()
                    Text("steps")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if stepsService.todaySteps >= 10000 {
                        Text("Goal Met! 🎉")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.top, 4)
                    } else {
                        Text("\(10000 - stepsService.todaySteps) to go")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            .frame(height: 220)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    private var weeklyHistory: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.headline)
                .padding(.horizontal)
            
            if stepsService.last7Days.isEmpty {
                Text("No data available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(stepsService.last7Days) { day in
                    HStack {
                        Text(formatDate(day.date))
                            .font(.subheadline)
                            .frame(width: 100, alignment: .leading)
                        
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 24)
                            
                            if let steps = day.steps {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(steps >= 10000 ? Color.green : Color.blue)
                                    .frame(width: CGFloat(min(steps, 10000)) / 10000 * 200, height: 24)
                            }
                        }
                        .frame(width: 200)
                        
                        if let steps = day.steps {
                            Text("\(steps)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(steps >= 10000 ? .green : .secondary)
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    private var syncStatus: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading) {
                    Text("Sync Status")
                        .font(.subheadline.weight(.semibold))
                    
                    if stepsService.isSyncing {
                        Text("Syncing...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let lastSync = stepsService.lastSyncDate {
                        Text("Last synced: \(lastSync, style: .relative) ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never synced")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let error = stepsService.lastSyncError {
                        Text("Error: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                Button {
                    Task { await syncNow() }
                } label: {
                    if stepsService.isSyncing {
                        ProgressView()
                    } else {
                        Text("Sync Now")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(stepsService.isSyncing)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
    }
    
    private func loadInitialData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Request authorization if needed
            try await stepsService.requestAuthorization()
            
            // Fetch steps
            _ = try await stepsService.fetchTodaySteps()
            _ = try await stepsService.fetchLast7Days()
            
            // Enable background delivery
            stepsService.enableBackgroundDelivery()
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    private func refreshSteps() async {
        do {
            _ = try await stepsService.fetchTodaySteps()
            _ = try await stepsService.fetchLast7Days()
        } catch {
            self.error = error.localizedDescription
        }
        await StepsTrackingService.syncBodyMeasurementsFromHealth()
    }
    
    private func syncNow() async {
        do {
            try await stepsService.syncStepsToBackend()
            _ = try await stepsService.fetchTodaySteps()
            _ = try await stepsService.fetchLast7Days()
        } catch {
            self.error = error.localizedDescription
            await StepsTrackingService.syncBodyMeasurementsFromHealth()
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "EEE M/d"
            return formatter.string(from: date)
        }
    }
}
