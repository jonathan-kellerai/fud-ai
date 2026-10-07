import SwiftUI

/// The Troubleshooting card in AI Providers: Test connection, Test meal photo, the last
/// result, and the request log. The tests themselves live in `AIDiagnostics`.
struct AIDiagnosticsSection: View {
    let store: AIRequestLogStore
    @State private var running: AIRequestLogEntry.Kind?
    @State private var result: AIDiagnosticResult?

    /// `result` lets Visual QA draw a finished test without a network call.
    init(store: AIRequestLogStore = .shared, result: AIDiagnosticResult? = nil) {
        self.store = store
        _result = State(initialValue: result)
    }

    var body: some View {
        Section {
            Label {
                Text("TROUBLESHOOTING")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } icon: {
                Image(systemName: "stethoscope")
            }
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(AppColors.calorie)
            .accessibilityAddTraits(.isHeader)

            testButton(
                "Test connection",
                systemImage: "bolt.horizontal.circle",
                kind: .connectionTest,
                identifier: "settings.aiDiagnostics.testConnection"
            ) {
                await AIDiagnostics.testConnection(store: store)
            }

            testButton(
                "Test meal photo",
                systemImage: "fork.knife.circle",
                kind: .sampleMealPhoto,
                identifier: "settings.aiDiagnostics.testMealPhoto"
            ) {
                await AIDiagnostics.testMealPhoto(store: store)
            }

            if let result {
                AIDiagnosticResultView(result: result)
            }

            NavigationLink {
                AIRequestLogListView(store: store)
            } label: {
                HStack {
                    Label {
                        Text("Request log")
                            .foregroundStyle(IronTheme.textPrimary)
                    } icon: {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(AppColors.calorie)
                    }
                    Spacer(minLength: 8)
                    Text("\(store.entries.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(IronTheme.textSecondary)
                }
            }
            .accessibilityIdentifier("settings.aiDiagnostics.requestLog")

            Text("Tests use your Photo & Text provider. The log of meal requests stays on this iPhone, with keys and tokens removed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(AppColors.appCard)
    }

    private func testButton(
        _ title: String,
        systemImage: String,
        kind: AIRequestLogEntry.Kind,
        identifier: String,
        run: @escaping @MainActor () async -> AIDiagnosticResult
    ) -> some View {
        Button {
            running = kind
            Task {
                let finished = await run()
                result = finished
                running = nil
            }
        } label: {
            HStack {
                Label {
                    Text(title)
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(AppColors.calorie)
                }
                Spacer(minLength: 8)
                if running == kind {
                    ProgressView()
                }
            }
        }
        .disabled(running != nil)
        .accessibilityIdentifier(identifier)
    }
}

/// One finished test: passed or failed, who answered, how long, and the answer or error.
struct AIDiagnosticResultView: View {
    let result: AIDiagnosticResult
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(providerLine)
                .font(.footnote)
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            switch result.outcome {
            case .success(let summary, let foods):
                Text(summary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(foods, id: \.self) { food in
                    Text(food)
                        .font(.footnote)
                        .foregroundStyle(IronTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .failure(let status, let message, let body):
                Text(status.map { "HTTP \($0)" } ?? "No HTTP response")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(IronTheme.bloodText)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let body {
                    Text(body)
                        .font(.caption.monospaced())
                        .foregroundStyle(IronTheme.textSecondary)
                        .lineLimit(10)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.aiDiagnostics.result")
    }

    @ViewBuilder
    private var header: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        layout {
            IronStatusPill(text: result.succeeded ? "Passed" : "Failed", tone: result.succeeded ? .olive : .blood)
            Text(result.kind.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(IronTheme.textPrimary)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            Text("\(result.latencyMs) ms")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(IronTheme.textSecondary)
        }
    }

    private var providerLine: String {
        "\(result.provider) · \(result.model ?? "no model")"
    }
}
