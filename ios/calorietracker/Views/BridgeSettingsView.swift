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
                    Task { await testConnection() }
                } label: {
                    HStack {
                        if isTestingConnection {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text("Test Connection")
                        Spacer()
                        if let result = testResult {
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
                
                if let error = syncService.lastSyncError {
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
                Button("Save Settings") {
                    saveSettings()
                }
                .disabled(baseURL.isEmpty)
            }
        }
        .navigationTitle("Training Bridge")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func testConnection() async {
        isTestingConnection = true
        testResult = nil
        defer { isTestingConnection = false }
        
        // Temporarily update service settings for test
        let originalSettings = NeonBridgeService.shared.settings
        NeonBridgeService.shared.settings = NeonBridgeSettings(
            baseURL: baseURL,
            apiKey: apiKey.isEmpty ? nil : apiKey
        )
        
        do {
            let health = try await NeonBridgeService.shared.checkHealth()
            testSuccess = health.ok
            testResult = "Connected! Program: \(health.programVersion)"
        } catch {
            testSuccess = false
            testResult = error.localizedDescription
        }
        
        // Restore original settings if test failed
        if !testSuccess {
            NeonBridgeService.shared.settings = originalSettings
        }
    }
    
    private func saveSettings() {
        settings = NeonBridgeSettings(
            baseURL: baseURL,
            apiKey: apiKey.isEmpty ? nil : apiKey
        )
        settings.save()
        NeonBridgeService.shared.settings = settings
        testResult = "Settings saved"
        testSuccess = true
    }
}
