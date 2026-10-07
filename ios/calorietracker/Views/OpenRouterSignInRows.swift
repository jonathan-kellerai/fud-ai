import SwiftUI

/// OpenRouter's rows in the Photo & Text card.
/// Signed in: who, and Sign out. Signed out: Sign in, the manual key field, and the
/// Paste code fallback once a sign-in has been tried.
struct OpenRouterSignInRows<KeyField: View>: View {
    @State private var ownSignIn: OpenRouterSignIn
    /// Visual QA puts a sign-in with a fixed state here, so shots never depend on the Keychain.
    @Environment(OpenRouterSignIn.self) private var injectedSignIn: OpenRouterSignIn?
    @Binding var apiKeyText: String
    let baseURL: String
    private let keyField: KeyField
    @State private var pastedCode = ""
    @Environment(\.openURL) private var openURL

    init(apiKeyText: Binding<String>, baseURL: String, @ViewBuilder keyField: () -> KeyField) {
        _ownSignIn = State(initialValue: OpenRouterSignIn.live())
        _apiKeyText = apiKeyText
        self.baseURL = baseURL
        self.keyField = keyField()
    }

    private var signIn: OpenRouterSignIn {
        injectedSignIn ?? ownSignIn
    }

    var body: some View {
        if signIn.isSignedIn {
            signedInRow
        } else {
            signInButton
            keyField
            if signIn.isAwaitingPastedCode {
                pasteCodeRows
            } else if signIn.hasTriedSignIn {
                pasteCodeButton
            }
            if let message = signIn.failureMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(IronTheme.bloodText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings.openrouter.error")
            }
        }
    }

    private var signedInRow: some View {
        AdaptiveLabelValue {
            Label {
                Text("Signed in with OpenRouter")
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(AppColors.calorie)
            }
        } value: {
            Button {
                signIn.signOut()
                apiKeyText = ""
            } label: {
                Text("Sign out")
                    .foregroundStyle(IronTheme.bloodText)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("settings.openrouter.signOut")
        }
        .accessibilityElement(children: .contain)
    }

    private var signInButton: some View {
        Button {
            Task {
                if let key = await signIn.signIn() { adopt(key) }
            }
        } label: {
            HStack {
                Label {
                    Text("Sign in with OpenRouter")
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "person.badge.key.fill")
                        .foregroundStyle(AppColors.calorie)
                }
                Spacer(minLength: 8)
                if signIn.isBusy {
                    ProgressView()
                }
            }
        }
        .disabled(signIn.isBusy)
        .accessibilityIdentifier("settings.openrouter.signIn")
    }

    private var pasteCodeButton: some View {
        Button {
            if let url = signIn.beginPasteCode() { openURL(url) }
        } label: {
            Label {
                Text("Paste code instead")
                    .foregroundStyle(IronTheme.textPrimary)
            } icon: {
                Image(systemName: "doc.on.clipboard")
                    .foregroundStyle(AppColors.calorie)
            }
        }
        .accessibilityIdentifier("settings.openrouter.pasteCode")
    }

    @ViewBuilder
    private var pasteCodeRows: some View {
        Text("Approve JL Physical on the OpenRouter page, copy the code it shows, then paste it here.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        AdaptiveLabelValue {
            Label {
                Text("Code")
            } icon: {
                Image(systemName: "number")
                    .foregroundStyle(AppColors.calorie)
            }
        } value: {
            TextField("Paste code", text: $pastedCode)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("settings.openrouter.code")
        }

        Button {
            Task {
                if let key = await signIn.submitPastedCode(pastedCode) { adopt(key) }
            }
        } label: {
            HStack {
                Label {
                    Text("Use code")
                        .foregroundStyle(IronTheme.textPrimary)
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(AppColors.calorie)
                }
                Spacer(minLength: 8)
                if signIn.isBusy {
                    ProgressView()
                }
            }
        }
        .disabled(signIn.isBusy || pastedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("settings.openrouter.useCode")

        Button {
            signIn.cancelPasteCode()
            pastedCode = ""
        } label: {
            Text("Cancel")
                .foregroundStyle(IronTheme.textSecondary)
        }
        .accessibilityIdentifier("settings.openrouter.cancelCode")
    }

    /// The key is already in the Keychain; this updates the screen and the model list.
    private func adopt(_ key: String) {
        apiKeyText = key
        pastedCode = ""
        ModelCatalogService.shared.scheduleRefresh(provider: .openrouter, baseURL: baseURL, apiKey: key)
    }
}
