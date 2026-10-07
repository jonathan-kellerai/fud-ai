import SwiftUI
import UIKit
import XCTest
@testable import calorietracker

/// Build 69 shots 120-126 (default + axL, Pro + small): OpenRouter sign-in states, the
/// key-only footnote, test results and the request log. Synthetic data only, no network:
/// results and log entries are fixtures pinned to `VisualQAFixtures.referenceNow`, and the
/// log screens read a temp-file store.
extension VisualQASnapshotTests {
    func test120AIProvidersOpenRouterSignedOut() async throws {
        let restore = VisualQAAIFixtures.pinSettings(provider: .openrouter)
        defer { restore() }
        let store = try VisualQAAIFixtures.store()
        try await capture("120-ai-providers-openrouter-signed-out", heightMultiplier: 2) { _ in
            VisualQAAIProvidersScreen(store: store, signedIn: false)
        }
    }

    func test121AIProvidersOpenRouterSignedIn() async throws {
        let restore = VisualQAAIFixtures.pinSettings(provider: .openrouter)
        defer { restore() }
        let store = try VisualQAAIFixtures.store()
        try await capture("121-ai-providers-openrouter-signed-in", heightMultiplier: 2) { _ in
            VisualQAAIProvidersScreen(store: store, signedIn: true)
        }
    }

    func test122AIProvidersXAIKeyOnly() async throws {
        let restore = VisualQAAIFixtures.pinSettings(provider: .xai)
        defer { restore() }
        let store = try VisualQAAIFixtures.store()
        try await capture("122-ai-providers-xai-key-only", heightMultiplier: 2) { _ in
            VisualQAAIProvidersScreen(store: store, signedIn: false)
        }
    }

    func test123AITestResultSuccess() async throws {
        let store = try VisualQAAIFixtures.store()
        try await capture("123-ai-test-result-success", heightMultiplier: 1.6) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") {
                    VisualQAAIDiagnosticsCard(store: store, result: VisualQAAIFixtures.successResult)
                }
            }
        }
    }

    func test124AITestResultError() async throws {
        let store = try VisualQAAIFixtures.store()
        try await capture("124-ai-test-result-error", heightMultiplier: 1.6) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "More") {
                    VisualQAAIDiagnosticsCard(store: store, result: VisualQAAIFixtures.errorResult)
                }
            }
        }
    }

    func test125AIRequestLogList() async throws {
        let store = try VisualQAAIFixtures.store()
        try await capture("125-ai-request-log-list", heightMultiplier: 2) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "AI Providers") { AIRequestLogListView(store: store) }
            }
        }
    }

    func test126AIRequestLogDetail() async throws {
        let entry = VisualQAAIFixtures.entries[1]
        try await capture("126-ai-request-log-detail", heightMultiplier: 1.6) { _ in
            VisualQATabShell(selected: .more) {
                VisualQAPushed(rootTitle: "Request log") { AIRequestLogDetailView(entry: entry) }
            }
        }
    }
}

/// More → AI Providers with a fixture request log, a fixed OpenRouter sign-in state and
/// fixed TypeSafe/Jev settings (off, no key, so no catalog refresh or Keychain read).
/// Pair with `VisualQAAIFixtures.pinSettings(provider:)` so no saved setting or key shows.
@MainActor
struct VisualQAAIProvidersScreen: View {
    let store: AIRequestLogStore
    let signIn: OpenRouterSignIn
    let typeSafe = TypeSafeSectionFixture(
        enabled: false,
        routerEnabled: false,
        endpoint: .direct,
        model: TypeSafeEndpoint.direct.defaultModel,
        checkTypedMeals: true,
        apiKey: ""
    )

    init(store: AIRequestLogStore, signedIn: Bool) {
        self.store = store
        signIn = OpenRouterSignIn(isSignedIn: signedIn)
    }

    var body: some View {
        VisualQATabShell(selected: .more) {
            VisualQAPushed(rootTitle: "More") {
                ProfileView(settingsCategory: .aiProviders)
                    .environment(store)
                    .environment(signIn)
                    .environment(typeSafe)
            }
        }
    }
}

/// The Troubleshooting card alone, styled like the AI Providers list it sits in.
struct VisualQAAIDiagnosticsCard: View {
    let store: AIRequestLogStore
    let result: AIDiagnosticResult

    var body: some View {
        List {
            AIDiagnosticsSection(store: store, result: result)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("AI Providers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
enum VisualQAAIFixtures {
    /// Pins every setting the AI Providers screen shows for one shot: `provider` on its
    /// default model, no saved API keys or custom server, no separate text AI, fallbacks
    /// or custom instructions, and on-device speech. Returns how to put the old values
    /// back. The shot then never depends on what the simulator's Keychain or defaults held.
    static func pinSettings(provider: AIProvider) -> () -> Void {
        let previousProvider = AIProviderSettings.selectedProvider
        let previousModel = AIProviderSettings.selectedModel
        let previousKeys = AIProvider.allCases.map { ($0, AIProviderSettings.apiKey(for: $0)) }
        let previousBaseURL = AIProviderSettings.customBaseURL(for: provider)
        let previousSeparateText = AIProviderSettings.separateTextProviderEnabled
        let previousFallback = AIProviderSettings.fallbackEnabled
        let previousTextFallback = AIProviderSettings.textFallbackEnabled
        let previousUserContext = AIProviderSettings.userContext
        let previousReasoningEffort = AIProviderSettings.openRouterReasoningEffort
        let previousSpeechProvider = SpeechSettings.selectedProvider
        let previousSpeechLanguage = SpeechSettings.selectedLanguage(for: .nativeIOS)
        let previousSpeechFallback = SpeechSettings.fallbackEnabled

        AIProviderSettings.selectedProvider = provider
        AIProviderSettings.selectedModel = provider.defaultModel
        for (keyProvider, _) in previousKeys {
            AIProviderSettings.setAPIKey(nil, for: keyProvider)
        }
        AIProviderSettings.setCustomBaseURL(nil, for: provider)
        AIProviderSettings.separateTextProviderEnabled = false
        AIProviderSettings.fallbackEnabled = false
        AIProviderSettings.textFallbackEnabled = false
        AIProviderSettings.userContext = ""
        AIProviderSettings.openRouterReasoningEffort = .auto
        SpeechSettings.selectedProvider = .nativeIOS
        SpeechSettings.setLanguage(SpeechSettings.defaultLanguage(for: .nativeIOS), for: .nativeIOS)
        SpeechSettings.fallbackEnabled = false

        return {
            AIProviderSettings.selectedProvider = previousProvider
            AIProviderSettings.selectedModel = previousModel
            for (keyProvider, key) in previousKeys {
                AIProviderSettings.setAPIKey(key, for: keyProvider)
            }
            AIProviderSettings.setCustomBaseURL(previousBaseURL, for: provider)
            AIProviderSettings.separateTextProviderEnabled = previousSeparateText
            AIProviderSettings.fallbackEnabled = previousFallback
            AIProviderSettings.textFallbackEnabled = previousTextFallback
            AIProviderSettings.userContext = previousUserContext
            AIProviderSettings.openRouterReasoningEffort = previousReasoningEffort
            SpeechSettings.selectedProvider = previousSpeechProvider
            SpeechSettings.setLanguage(previousSpeechLanguage, for: .nativeIOS)
            SpeechSettings.fallbackEnabled = previousSpeechFallback
        }
    }

    /// A fresh temp-file log holding `entries`, so the shots never read the device log.
    static func store() throws -> AIRequestLogStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("visual-qa-ai-log-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AIRequestLogStore(fileURL: directory.appendingPathComponent("ai-request-log.json"))
        store.append(Array(entries.reversed()))
        return store
    }

    private static func minutesAgo(_ minutes: Double) -> Date {
        VisualQAFixtures.referenceNow.addingTimeInterval(-minutes * 60)
    }

    /// Newest first, as the list shows them. Keys in bodies are already redacted, as stored.
    static let entries: [AIRequestLogEntry] = [
        AIRequestLogEntry(
            id: UUID(uuidString: "00000000-0000-0000-0069-000000000001")!,
            timestamp: minutesAgo(2),
            provider: "OpenRouter",
            model: "openai/gpt-5-mini",
            kind: .mealPhoto,
            httpStatus: 200,
            latencyMs: 2_140,
            errorBody: nil,
            parsed: true
        ),
        AIRequestLogEntry(
            id: UUID(uuidString: "00000000-0000-0000-0069-000000000002")!,
            timestamp: minutesAgo(15),
            provider: "xAI Grok",
            model: "grok-4",
            kind: .textFood,
            httpStatus: 401,
            latencyMs: 312,
            errorBody: #"{"code":"Client specified an invalid argument","error":"Incorrect API key provided: [REDACTED]. You can obtain an API key from https://console.x.ai."}"#,
            parsed: false
        ),
        AIRequestLogEntry(
            id: UUID(uuidString: "00000000-0000-0000-0069-000000000003")!,
            timestamp: minutesAgo(40),
            provider: "Google Gemini",
            model: "gemini-2.5-flash",
            kind: .mealPhoto,
            httpStatus: 503,
            latencyMs: 7_480,
            errorBody: #"{"error":{"code":503,"message":"The model is overloaded. Please try again later.","status":"UNAVAILABLE"}}"#,
            parsed: false
        ),
        AIRequestLogEntry(
            id: UUID(uuidString: "00000000-0000-0000-0069-000000000004")!,
            timestamp: minutesAgo(65),
            provider: "OpenRouter",
            model: "openai/gpt-5-mini",
            kind: .sampleMealPhoto,
            httpStatus: 200,
            latencyMs: 3_020,
            errorBody: "Could not understand the AI response. Please try again.\nResponse: I can see a plate with grilled chicken, white rice and broccoli.",
            parsed: false
        ),
        AIRequestLogEntry(
            id: UUID(uuidString: "00000000-0000-0000-0069-000000000005")!,
            timestamp: minutesAgo(120),
            provider: AIRequestTrace.hostedProviderName,
            model: nil,
            kind: .connectionTest,
            httpStatus: nil,
            latencyMs: 940,
            errorBody: nil,
            parsed: true
        ),
        AIRequestLogEntry(
            id: UUID(uuidString: "00000000-0000-0000-0069-000000000006")!,
            timestamp: minutesAgo(180),
            provider: "OpenAI",
            model: "gpt-5",
            kind: .mealPhoto,
            httpStatus: nil,
            latencyMs: 0,
            errorBody: "No API key configured. Add your key in Settings → AI Provider.",
            parsed: false
        ),
    ]

    static let successResult = AIDiagnosticResult(
        kind: .sampleMealPhoto,
        provider: "OpenRouter",
        model: "openai/gpt-5-mini",
        latencyMs: 2_140,
        outcome: .success(
            summary: "Grilled chicken, rice & broccoli · 640 kcal",
            foods: ["Grilled chicken · 280 kcal", "White rice · 260 kcal", "Broccoli · 100 kcal"]
        )
    )

    static let errorResult = AIDiagnosticResult(
        kind: .connectionTest,
        provider: "xAI Grok",
        model: "grok-4",
        latencyMs: 312,
        outcome: .failure(
            status: 401,
            message: "Your API key was rejected. Open Settings → AI Provider and re-paste a valid key.",
            body: #"{"code":"Client specified an invalid argument","error":"Incorrect API key provided: [REDACTED]. You can obtain an API key from https://console.x.ai."}"#
        )
    )
}
