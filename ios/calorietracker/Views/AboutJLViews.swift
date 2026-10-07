import SwiftUI

enum JLAppVersion {
    static var shortAndBuild: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        if short.isEmpty { return build }
        if build.isEmpty { return short }
        return "\(short) (\(build))"
    }
}

struct AboutView: View {
    private static let feedbackURL = URL(string: "https://github.com/jonathan-kellerai/fud-ai/issues/new")!

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image("JLPhysicalAppIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                    Text("JL Physical")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text("Version \(JLAppVersion.shortAndBuild)")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(AppColors.appCard)

            Section {
                NavigationLink(value: ProfileSettingsCategory.acknowledgements) {
                    SettingsHubRowLabel(
                        title: "Acknowledgements",
                        systemImage: "text.book.closed",
                        subtitle: "Based on Fud AI by Apoorv Darshan (MIT)"
                    )
                }
                Link(destination: Self.feedbackURL) {
                    Label("Send Feedback", systemImage: "exclamationmark.bubble")
                }
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .settingsFloatingTabClearance()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AcknowledgementsView: View {
    @State private var licenseExpanded = false

    var body: some View {
        List {
            Section {
                Button {
                    licenseExpanded.toggle()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Fud AI · MIT License")
                            .foregroundStyle(.primary)
                        if licenseExpanded {
                            Text(Self.mitLicense)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                Link(destination: URL(string: "https://github.com/apoorvdarshan/fud-ai")!) {
                    Label("View upstream project", systemImage: "arrow.up.forward.square")
                }
                NavigationLink {
                    LiteRTLMNoticesView()
                } label: {
                    Text(LocalModelStrings.text("notices.legalRow", defaultValue: "LiteRT-LM Third-Party Notices"))
                }
                NavigationLink {
                    WhisperBaseNoticesView()
                } label: {
                    Text("Whisper Base · WhisperKit (MIT)")
                }
                Link(destination: Gemma4LocalModelManager.licenseURL) {
                    Label("Gemma 4 · Apache 2.0", systemImage: "arrow.up.forward.square")
                }
            } footer: {
                Text("Based on Fud AI by Apoorv Darshan (MIT).")
            }
            .listRowBackground(AppColors.appCard)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .settingsFloatingTabClearance()
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let mitLicense = """
    MIT License

    Copyright (c) 2026 Apoorv Darshan

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
}
