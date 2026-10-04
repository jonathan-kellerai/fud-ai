import SwiftUI

/// Small Iron & Blood building blocks shared by the Challenges and Peptides screens.
/// Section headers reuse `IronSectionTitle`.

/// A short uppercase status word ("BEHIND", "LOGGED") in a tinted capsule.
struct IronStatusPill: View {
    enum Tone: Hashable, Sendable {
        case blood
        case brass
        case olive
        case rust
        case neutral

        var color: Color {
            switch self {
            case .blood: IronTheme.bloodText
            case .brass: IronTheme.brass
            case .olive: IronTheme.olive
            case .rust: IronTheme.rust
            case .neutral: IronTheme.textSecondary
            }
        }
    }

    let text: String
    let tone: Tone
    @ScaledMetric(relativeTo: .caption) private var horizontalPadding: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var verticalPadding: CGFloat = 3

    var body: some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .fontWidth(.condensed)
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(tone.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(tone.color.opacity(IronTheme.pillFillOpacity), in: Capsule())
            .overlay(Capsule().strokeBorder(tone.color.opacity(IronTheme.borderTintOpacity), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityText(for: text))
    }

    nonisolated static func accessibilityText(for text: String) -> String {
        "Status: \(text.lowercased())."
    }
}

/// A labelled number: small label on top, a large value, optional detail below. Wraps, never truncates.
struct IronStatTile: View {
    let label: String
    let value: String
    var detail: String?
    var valueColor: Color = IronTheme.textPrimary

    @ScaledMetric(relativeTo: .title2) private var padding: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.heavy))
                .fontWidth(.condensed)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textSecondary)
            Text(value)
                .font(.title2.weight(.heavy).monospacedDigit())
                .fontWidth(.condensed)
                .foregroundStyle(valueColor)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(IronTheme.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .ironCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText(label: label, value: value, detail: detail))
    }

    nonisolated static func accessibilityText(label: String, value: String, detail: String?) -> String {
        let main = "\(label.capitalized): \(value)."
        guard let detail, !detail.isEmpty else { return main }
        return "\(main) \(detail)."
    }
}
