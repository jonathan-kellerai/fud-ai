import SwiftUI

struct EstimateCheckBadge: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var expectedBandLabel: String
    var onReestimate: (() -> Void)?

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
                    UnbrokenText("TypeSafe expects closer to \(expectedBandLabel)")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
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
