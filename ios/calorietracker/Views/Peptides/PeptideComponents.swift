//
//  PeptideComponents.swift
//  calorietracker
//
//  Iron & Blood building blocks for the Peptides screens. Blood red is only
//  a fill or an accent bar here, never text; rust text is large and bold.
//

import SwiftUI

/// Condensed heavy uppercase screen title.
struct PeptideScreenTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 28, weight: .black))
                .fontWidth(.condensed)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small condensed label above a field or inside a card. Brass, like the
/// design's labels; scales with Dynamic Type.
struct PeptideFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(.caption, design: .default, weight: .heavy))
            .fontWidth(.condensed)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(IronTheme.brass)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Today | Week | Vials. Brass marks the selected tab (black text on it).
/// At large text sizes the three stack instead of truncating.
enum PeptideTab: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case vials = "Vials"

    var id: String { rawValue }
}

struct PeptideTabPicker: View {
    @Binding var tab: PeptideTab

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { segments }
            VStack(spacing: 0) { segments }
        }
        .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                .stroke(IronTheme.brass, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Peptides section")
    }

    private var segments: some View {
        ForEach(PeptideTab.allCases) { item in
            let selected = tab == item
            Button {
                tab = item
            } label: {
                Text(item.rawValue)
                    .font(.system(.subheadline, design: .default, weight: .heavy))
                    .fontWidth(.condensed)
                    .textCase(.uppercase)
                    .fixedSize()
                    .foregroundStyle(selected ? IronTheme.canvas : IronTheme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.horizontal, 8)
                    .background(selected ? IronTheme.brass : IronTheme.surface)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("peptides.tab." + item.rawValue.lowercased())
        }
    }
}

/// Condensed heavy brass header ("TODAY · WED 7 OCT"). Wraps, never truncates.
struct PeptideHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.title2, design: .default, weight: .black))
            .fontWidth(.condensed)
            .textCase(.uppercase)
            .foregroundStyle(IronTheme.brass)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// A 6 pt squared card with a coloured accent bar on its leading edge
    /// (olive: confirmed, rust: not confirmed, brass: neutral). The bar is
    /// never text.
    func peptideAccentCard(_ accent: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: IronTheme.cardRadius, style: .continuous)
        return self
            .padding(.leading, IronTheme.ruleWidth)
            .background(IronTheme.surface)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent)
                    .frame(width: IronTheme.ruleWidth + 1)
                    .accessibilityHidden(true)
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(IronTheme.hairline, lineWidth: 1) }
    }
}

/// One saved draw, like a finished set: compound, the draw as typed, time,
/// vial. Olive bar when its vial was confirmed at save, rust when not, brass
/// with no vial. Never shows mg (not even to VoiceOver).
struct PeptideRecordCard: View {
    let entry: PeptideLogEntry
    var vialName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.compound.isEmpty ? "Draw" : entry.compound)
                .font(.system(.title3, design: .default, weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            PeptideDetailRow(label: "Draw", value: entry.drawText ?? "Not recorded")
            PeptideDetailRow(label: "Time", value: entry.date.map(PeptideMath.timeText) ?? entry.datetimeRaw)
            if let vialName {
                PeptideDetailRow(label: "Vial", value: vialName)
            }
            if entry.voided {
                Text("Voided")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .peptideAccentCard(accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var accent: Color {
        guard entry.vialID != nil else { return IronTheme.brass }
        return entry.concentrationConfirmedAtSave ? IronTheme.olive : IronTheme.rust
    }

    /// "BPC-157, 50 units, 7:30 AM, vial BPC-157. Concentration confirmed."
    private var spokenLabel: String {
        var parts = [entry.compound]
        if let value = entry.drawnVolume, let unit = entry.drawnUnit {
            parts.append(PeptideMath.drawSpokenText(value, unit))
        } else {
            parts.append("draw not recorded")
        }
        if let date = entry.date {
            parts.append(PeptideMath.timeText(date).replacingOccurrences(of: " ET", with: ""))
        }
        if let vialName { parts.append("vial " + vialName) }
        var text = parts.joined(separator: ", ") + "."
        if entry.vialID != nil {
            text += entry.concentrationConfirmedAtSave ? " Concentration confirmed." : " Concentration not confirmed."
        }
        if entry.voided { text += " Voided." }
        return text
    }
}

/// Wraps chips onto as many lines as the width needs (iPhone SE, large text).
struct PeptideFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let frames = arrange(subviews: subviews, maxWidth: maxWidth)
        var width: CGFloat = 0
        var height: CGFloat = 0
        for frame in frames {
            width = max(width, frame.maxX)
            height = max(height, frame.maxY)
        }
        if let proposed = proposal.width, proposed.isFinite {
            width = proposed
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews: subviews, maxWidth: bounds.width)
        for (index, subview) in subviews.enumerated() where index < frames.count {
            let frame = frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if maxWidth.isFinite && size.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            if x > 0 && maxWidth.isFinite && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}

/// Tappable chip. Selected chips fill with blood. Text scales with Dynamic
/// Type and wraps; the chip is at least 44 pt tall at every size.
struct PeptideChoiceChip: View {
    let title: String
    var subtitle: String?
    let selected: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var verticalPadding: CGFloat = 8

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.subheadline, weight: .heavy))
                    .fontWidth(.condensed)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(selected ? IronTheme.textPrimary : IronTheme.textSecondary)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(selected ? IronTheme.textPrimary : IronTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, verticalPadding)
            .frame(minWidth: 44, minHeight: 44)
            .background(
                selected ? IronTheme.blood : IronTheme.surfaceRaised,
                in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                    .stroke(selected ? IronTheme.blood : IronTheme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Small status tag. Text tone is a theme color on the raised surface.
struct PeptideTag: View {
    let text: String
    let tone: Color
    var filled = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .fontWidth(.condensed)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(filled ? IronTheme.textPrimary : tone)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                filled ? tone : IronTheme.surfaceRaised,
                in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                    .stroke(tone, lineWidth: 1)
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Outlined secondary action, at least 44 pt tall at every text size.
struct PeptideSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .heavy))
            .textCase(.uppercase)
            .multilineTextAlignment(.center)
            .foregroundStyle(IronTheme.brass)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 12)
            .background(
                configuration.isPressed ? IronTheme.surface : IronTheme.surfaceRaised,
                in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                    .stroke(IronTheme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
    }
}

/// Decimal or text field in the Peptides input style.
struct PeptideInputField: View {
    let title: String
    @Binding var text: String
    var prompt: String = ""
    var keyboard: UIKeyboardType = .default
    var monospaced = false
    var issue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PeptideFieldLabel(title)
            TextField(prompt.isEmpty ? title : prompt, text: $text)
                .keyboardType(keyboard)
                .font(monospaced ? .system(.title3, design: .monospaced) : .system(.body, design: .rounded))
                .foregroundStyle(IronTheme.textPrimary)
                .padding(10)
                .background(IronTheme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                        .stroke(issue == nil ? IronTheme.hairline : IronTheme.rust, lineWidth: 1)
                )
            if let issue {
                PeptideIssueText(text: issue)
            }
        }
    }
}

struct PeptideIssueText: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(IronTheme.textPrimary)
        } icon: {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(IronTheme.rust)
        }
        .font(.system(.footnote, design: .rounded, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Outlined notice. Rust for warnings, brass for pending, blood text for errors.
struct PeptideBanner: View {
    let title: String
    var message: String?
    var tone: Color = IronTheme.rust
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(tone)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(IronCompactButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(IronTheme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: IronTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: IronTheme.cardRadius, style: .continuous)
                .stroke(tone, lineWidth: 1)
        )
    }
}

/// "Label  value" that stacks at accessibility sizes. Values wrap, never truncate.
struct PeptideDetailRow: View {
    let label: String
    let value: String
    var valueColor: Color = IronTheme.textPrimary

    var body: some View {
        AdaptiveLabelValue {
            Text(label)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } value: {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PeptideFooter: View {
    var body: some View {
        Text(PeptideMath.footerText)
            .font(.system(size: 13))
            .foregroundStyle(IronTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Horizontal remaining bar. Olive, or rust when low.
struct PeptideRemainingBar: View {
    let fraction: Double
    let low: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(IronTheme.surfaceRaised)
                Rectangle()
                    .fill(low ? IronTheme.rust : IronTheme.olive)
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 2, style: .continuous).stroke(IronTheme.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Civil dates for date-only pickers use the device calendar so the picked
/// day never shifts.
enum PeptideViewDates {
    static func civil(fromLocal date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    static func localDate(fromCivil civil: String) -> Date {
        guard let parts = ReconMath.parseISO(civil) else { return Date() }
        var components = DateComponents()
        components.year = parts.year
        components.month = parts.month
        components.day = parts.day
        components.hour = 12
        return Calendar.current.date(from: components) ?? Date()
    }

    static func minutes(fromLocal date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    static func localDate(minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }
}
