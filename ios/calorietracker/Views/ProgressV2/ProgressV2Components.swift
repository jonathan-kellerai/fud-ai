import SwiftUI

// MARK: - Headers

/// Condensed heavy uppercase label, same treatment as IronSectionTitle but on
/// a scalable text style.
struct ProgressV2SectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(.subheadline, weight: .heavy))
                .fontWidth(.condensed)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Segmented control

/// Squared Iron segmented control. One row when every label fits, otherwise
/// a grid; at accessibility sizes always a grid so no label truncates.
struct ProgressV2SegmentedControl<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    let accessibilityLabel: String
    var accessibilityColumns: Int = 2
    var compactColumns: Int = 3
    /// VoiceOver label per segment when the visible one is an abbreviation.
    var spokenLabel: ((Option) -> String)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                grid(columns: accessibilityColumns)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 1) { segments }
                    grid(columns: compactColumns)
                    grid(columns: 1)
                }
            }
        }
        .background(IronTheme.hairline)
        .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                .strokeBorder(IronTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func grid(columns: Int) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: max(1, columns)),
            spacing: 1
        ) {
            segments
        }
    }

    private var segments: some View {
        ForEach(options, id: \.self) { option in
            let isSelected = option == selection
            Button {
                withAnimation(reduceMotion ? nil : IronTheme.motion) { selection = option }
            } label: {
                Text(label(option))
                    .font(.system(.subheadline, weight: .heavy))
                    .fontWidth(.condensed)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(isSelected ? IronTheme.textPrimary : IronTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(isSelected ? IronTheme.blood : IronTheme.surfaceRaised)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spokenLabel?(option) ?? label(option))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}

// MARK: - Stats

struct ProgressV2Stat: Identifiable {
    let label: String
    let value: String
    var accessibilityValue: String?
    var id: String { label }
}

/// Four stats in one row when they fit, 2 × 2 when they do not, and a
/// vertical list at accessibility sizes. Values never truncate.
struct ProgressV2StatGrid: View {
    let stats: [ProgressV2Stat]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            list
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(stats) { tile($0) }
                }
                pairs
                list
            }
        }
    }

    private var pairs: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { index in
                GridRow {
                    tile(stats[index])
                    if index + 1 < stats.count {
                        tile(stats[index + 1])
                    } else {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
            }
        }
    }

    private var list: some View {
        VStack(spacing: 8) {
            ForEach(stats) { tile($0) }
        }
    }

    private func tile(_ stat: ProgressV2Stat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stat.label)
                .font(.system(.caption, weight: .heavy))
                .fontWidth(.condensed)
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(stat.value)
                .font(.system(.title3, weight: .bold).monospacedDigit())
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.label)
        .accessibilityValue(stat.accessibilityValue ?? stat.value)
    }
}

// MARK: - Empty / loading

struct ProgressV2EmptyState: View {
    let title: String
    var message: String?
    var systemImage: String = "chart.xyaxis.line"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(IronTheme.textPrimary)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(IronTheme.textTertiary)
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(IronTheme.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .padding(12)
        .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct ProgressV2LoadingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(IronTheme.bloodText)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(IronTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Small squared swatch + label used by chart legends.
struct ProgressV2LegendItem: View {
    let title: String
    let color: Color
    var isLine: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: isLine ? 14 : 8, height: isLine ? 3 : 8)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundStyle(IronTheme.textSecondary)
        }
    }
}

// MARK: - Formatting

enum ProgressV2Format {
    static let dash = "—"

    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func signed(_ value: Double, digits: Int = 1) -> String {
        let magnitude = number(abs(value), digits: digits)
        let rounded = (abs(value) * pow(10, Double(digits))).rounded()
        if rounded == 0 { return magnitude }
        return (value < 0 ? "−" : "+") + magnitude
    }

    static func mass(_ value: Double?, unit: String) -> String {
        guard let value else { return dash }
        return "\(number(value)) \(unit)"
    }

    static func signedMass(_ value: Double?, unit: String) -> String {
        guard let value else { return dash }
        return "\(signed(value)) \(unit)"
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return dash }
        return "\(number(value))%"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func mediumDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func integer(_ value: Int) -> String {
        value.formatted(.number)
    }
}
