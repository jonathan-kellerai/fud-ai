import SwiftUI

/// The Photo & Text card's API key row. The key is saved to the Keychain as it is typed.
/// OpenRouter also offers sign-in; no other provider offers third-party apps a sign-in
/// (see docs/plans/build-69-ai-oauth-test-log.md), so they keep the key field and say so.
struct AIProviderAPIKeyRow: View {
    let provider: AIProvider
    /// Where the model catalog refresh looks, so a new key lists that provider's models.
    let baseURL: String
    @Binding var apiKeyText: String
    @Binding var showAPIKey: Bool

    var body: some View {
        if provider == .openrouter {
            OpenRouterSignInRows(apiKeyText: $apiKeyText, baseURL: baseURL) {
                keyField
            }
        } else {
            keyField
            Text("Sign-in isn't offered by \(provider.displayName); use an API key.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings.aiProvider.noSignIn")
        }
    }

    private var keyField: some View {
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
                        TextField(provider.apiKeyPlaceholder, text: $apiKeyText)
                    } else {
                        SecureField(provider.apiKeyPlaceholder, text: $apiKeyText)
                    }
                }
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: apiKeyText) { _, newValue in
                    let t = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    AIProviderSettings.setAPIKey(t.isEmpty ? nil : t, for: provider)
                    ModelCatalogService.shared.scheduleRefresh(
                        provider: provider,
                        baseURL: baseURL,
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
}
