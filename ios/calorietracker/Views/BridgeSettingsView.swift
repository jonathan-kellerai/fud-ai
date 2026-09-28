//
//  BridgeSettingsView.swift
//  calorietracker
//
//  Neon training bridge configuration
//

import SwiftUI

struct BridgeSettingsView: View {
    @State private var settings = NeonBridgeService.shared.settings
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var isTestingConnection = false
    @State private var testResult: String?
    @State private var testSuccess = false
    @State private var syncService = WorkoutSyncService.shared
    @State private var stepsService = StepsTrackingService.shared
    @State private var reconStore = ReconBenchStore()
    
    init() {
        let settings = NeonBridgeService.shared.settings
        _baseURL = State(initialValue: settings.baseURL)
        _apiKey = State(initialValue: settings.apiKey ?? "")
    }
    
    var body: some View {
        Form {
            Section {
                TextField("Bridge URL", text: $baseURL)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                
                Button("Reset to Default") {
                    baseURL = NeonBridgeSettings.defaultBaseURL
                }
                .disabled(baseURL == NeonBridgeSettings.defaultBaseURL)
            } header: {
                Text("Connection")
            } footer: {
                Text("The Neon training bridge endpoint for workout and steps sync.")
            }
            
            Section {
                SecureField("API Key (optional)", text: $apiKey)
                    .autocapitalization(.none)
            } header: {
                Text("Authentication")
            } footer: {
                Text("Optional Bearer token for authenticated requests.")
            }
            
            Section {
                Button {
                    Task { await saveAndTest() }
                } label: {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text("Save & Test")
                        Spacer()
                        if testResult != nil {
                            Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(testSuccess ? .green : .red)
                        }
                    }
                }
                .disabled(isTestingConnection || baseURL.isEmpty)
                
                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(testSuccess ? .green : .red)
                }
            }
            
            Section {
                HStack {
                    Text("Pending Workouts")
                    Spacer()
                    Text("\(syncService.syncQueue.count)")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Last Steps Sync") {
                    Text(lastStepsSyncLabel)
                        .foregroundStyle(.secondary)
                }
                
                if let error = syncService.lastSyncError ?? stepsService.lastSyncError {
                    VStack(alignment: .leading) {
                        Text("Last Error")
                            .font(.caption.weight(.semibold))
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Sync Status")
            }

            Section {
                Toggle("Sync Peptide Doses", isOn: Binding(
                    get: { reconStore.bridgeSyncEnabled },
                    set: { reconStore.bridgeSyncEnabled = $0 }
                ))
            } footer: {
                Text("Off by default. Taken Recon doses stay on this phone until this is on.")
            }
        }
        .navigationTitle("Neon Bridge")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lastStepsSyncLabel: String {
        guard let date = stepsService.lastSyncDate else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
    
    private func saveAndTest() async {
        isTestingConnection = true
        testResult = nil
        defer { isTestingConnection = false }

        saveSettings()

        do {
            let health = try await NeonBridgeService.shared.checkHealth()
            testSuccess = health.ok
            testResult = "Connected! Program: \(health.programVersion)"
        } catch {
            testSuccess = false
            testResult = error.localizedDescription
        }
    }
    
    private func saveSettings() {
        settings = NeonBridgeSettings(
            baseURL: baseURL,
            apiKey: apiKey.isEmpty ? nil : apiKey
        )
        settings.save()
        NeonBridgeService.shared.settings = settings
    }
}
