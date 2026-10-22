import SwiftUI
import UIKit

struct EstimateCheckBadge: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var expectedBandLabel: String
    var onReestimate: (() -> Void)?

    private static func subtitle(_ label: String) -> AttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.hyphenationFactor = 0
        paragraph.lineBreakStrategy = .pushOut
        let raw = NSAttributedString(
            string: "TypeSafe expects closer to \(label)",
            attributes: [.paragraphStyle: paragraph]
        )
        return AttributedString(raw)
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(IronTheme.brass)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    UnbrokenText("Estimate looks off")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                    Text(Self.subtitle(expectedBandLabel))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("foodReview.estimateCheck.badge")

            if let onReestimate {
                Button("Re-estimate", action: onReestimate)
                    .buttonStyle(.bordered)
                    .tint(IronTheme.brass)
                    .accessibilityIdentifier("foodReview.estimateCheck.reestimate")
            }
        }
    }
}
