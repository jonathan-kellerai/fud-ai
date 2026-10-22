import SwiftUI
import UIKit

struct SettingsHubRowLabel: View {
    let title: LocalizedStringResource
    let systemImage: String
    let subtitle: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                UnbrokenText(title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                UnbrokenText(subtitle)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.brass)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(IronTheme.bloodText)
                .frame(width: 24)
        }
    }
}

struct ProfileSettingsCategoryRow: View {
    let category: ProfileSettingsCategory
    let subtitle: String

    var body: some View {
        NavigationLink(value: category) {
            SettingsHubRowLabel(title: category.title, systemImage: category.systemImage, subtitle: subtitle)
        }
        .accessibilityIdentifier("settings.category.\(category.rawValue)")
        .overlay {
            SettingsHubRowAnchor(identifier: "settings.category.\(category.rawValue)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
        }
    }
}

/// Clear overlay so visual QA can measure hub rows without reading SwiftUI text views.
struct SettingsHubRowAnchor: UIViewRepresentable {
    let identifier: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        apply(identifier, to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.isUserInteractionEnabled = false
        uiView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        apply(identifier, to: uiView)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 320, height: 52))
    }

    private func apply(_ identifier: String, to view: UIView) {
        view.accessibilityIdentifier = identifier
        view.layer.name = identifier
    }
}
