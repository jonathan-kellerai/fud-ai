//
//  PeptideComponents.swift
//  calorietracker
//
//  Iron & Blood building blocks for the Peptides screens.
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

/// Small condensed label above a field or inside a card.
struct PeptideFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .heavy))
            .fontWidth(.condensed)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(IronTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Jonathan | Victoria, same look as Recon Bench's person switch.
struct PeptidePersonToggle: View {
    @Binding var person: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PeptidePerson.order, id: \.self) { key in
                let selected = PeptidePerson.normalized(person) == key
                Button {
                    person = key
                } label: {
                    Text(PeptidePerson.name(key))
                        .font(.system(size: 15, weight: .heavy))
                        .fontWidth(.condensed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? IronTheme.textPrimary : IronTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? IronTheme.blood : IronTheme.surfaceRaised)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                .stroke(IronTheme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Person")
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

/// Tappable chip. Selected chips fill with blood.
struct PeptideChoiceChip: View {
    let title: String
    var subtitle: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .fontWidth(.condensed)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? IronTheme.textPrimary : IronTheme.textSecondary)
                }
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(selected ? IronTheme.textPrimary : IronTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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

/// Synced (olive) / Pending (brass) / Failed (rust) / Peptide assistant (concrete).
struct PeptideSyncChip: View {
    let state: PeptideSyncState

    var body: some View {
        switch state {
        case .synced:
            PeptideTag(text: "Synced", tone: IronTheme.olive)
        case .pending:
            PeptideTag(text: "Pending", tone: IronTheme.brass)
        case .failed:
            PeptideTag(text: "Failed", tone: IronTheme.rust)
        case .readOnlyAgent:
            PeptideTag(text: "Peptide assistant", tone: IronTheme.concrete, filled: true)
        case .readOnly:
            PeptideTag(text: "Read-only", tone: IronTheme.concrete, filled: true)
        }
    }
}

/// Decimal or text field in the Recon Bench input style.
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
                        .stroke(issue == nil ? IronTheme.hairline : IronTheme.bloodText, lineWidth: 1)
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
        Label(text, systemImage: "exclamationmark.circle")
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(IronTheme.bloodText)
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

/// One administration in a list: compound, amount as stored, time ET, site, vial, sync chip.
struct PeptideLogRow: View {
    let entry: PeptideLogEntry
    var vialName: String?
    var showsPerson = false
    var onFailedTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.compound.isEmpty ? "Dose" : entry.compound)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(entry.voided ? IronTheme.textTertiary : IronTheme.textPrimary)
                    .strikethrough(entry.voided)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                chip
            }
            Text(PeptideMath.amountText(entry.dose, entry.units))
                .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(entry.voided ? IronTheme.textTertiary : IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(detailLine)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if entry.voided {
                Text("Voided" + (entry.voidReason.map { ": " + $0 } ?? ""))
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(IronTheme.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = entry.syncState.failureMessage {
                Text(message)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(IronTheme.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var chip: some View {
        if case .failed = entry.syncState, let onFailedTap {
            Button(action: onFailedTap) {
                PeptideSyncChip(state: entry.syncState)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Failed to sync. Retry or discard.")
        } else {
            PeptideSyncChip(state: entry.syncState)
        }
    }

    private var detailLine: String {
        var parts: [String] = []
        if showsPerson { parts.append(PeptidePerson.name(entry.person)) }
        if let date = entry.date {
            parts.append(PeptideMath.timeText(date))
        } else if !entry.datetimeRaw.isEmpty {
            parts.append(entry.datetimeRaw)
        }
        if let route = entry.route, !route.isEmpty { parts.append(route) }
        if let vialName { parts.append("Vial: " + vialName) }
        return parts.joined(separator: " · ")
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

/// Remembers Jonathan | Victoria between visits.
enum PeptidePersonMemory {
    static func load() -> String {
        let stored = UserDefaults.standard.string(forKey: PeptideLogStore.personKey) ?? PeptidePerson.jonathan
        return PeptidePerson.order.contains(stored) ? stored : PeptidePerson.jonathan
    }

    static func save(_ person: String) {
        UserDefaults.standard.set(PeptidePerson.normalized(person), forKey: PeptideLogStore.personKey)
    }
}
