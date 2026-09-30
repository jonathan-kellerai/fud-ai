import SwiftUI

/// Latest weight, body fat and measured lean mass, plus fat mass derived only
/// from a weight and a body-fat reading taken on the same day.
struct ProgressBodySummaryCard: View {
    let snapshot: ProgressCompositionSnapshot

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone

    private var massUnit: String { snapshot.useMetric ? "kg" : "lb" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressV2SectionTitle(
                title: String(localized: "Latest Readings"),
                detail: String(localized: "Most recent value of each, from any date.")
            )

            VStack(spacing: 1) {
                row(
                    label: String(localized: "Weight"),
                    value: snapshot.latestWeight.map { ProgressV2Format.mass($0.value, unit: massUnit, locale: locale) },
                    date: snapshot.latestWeight?.date,
                    caption: nil,
                    isDerived: false
                )
                row(
                    label: String(localized: "Body Fat"),
                    value: snapshot.latestBodyFat.map { ProgressV2Format.percent($0.value, locale: locale) },
                    date: snapshot.latestBodyFat?.date,
                    caption: nil,
                    isDerived: false
                )
                row(
                    label: String(localized: "Lean Mass"),
                    value: snapshot.latestLeanMass.map { ProgressV2Format.mass($0.value, unit: massUnit, locale: locale) },
                    date: snapshot.latestLeanMass?.date,
                    caption: leanCaption,
                    isDerived: false
                )
                if let derived = snapshot.derivedFatMass {
                    row(
                        label: String(localized: "Fat Mass"),
                        value: ProgressV2Format.mass(
                            ProgressV2Math.displayMass(kg: derived.fatMassKg, useMetric: snapshot.useMetric),
                            unit: massUnit,
                            locale: locale
                        ),
                        date: derived.day,
                        caption: derivedCaption(derived),
                        isDerived: true
                    )
                }
            }
            .background(IronTheme.hairline)
            .clipShape(RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
        }
        .padding(14)
        .ironCard()
    }

    private var leanCaption: String? {
        guard snapshot.latestLeanMass != nil else { return String(localized: "Comes from your scale via Apple Health") }
        if let source = snapshot.latestLeanMassSource, !source.isEmpty {
            return String(localized: "Measured · \(source)")
        }
        return String(localized: "Measured")
    }

    private func derivedCaption(_ derived: ProgressDerivedFatMass) -> String {
        let weight = ProgressV2Format.mass(
            ProgressV2Math.displayMass(kg: derived.weightKg, useMetric: snapshot.useMetric),
            unit: massUnit,
            locale: locale
        )
        let fat = ProgressV2Format.percent(derived.bodyFatFraction * 100, locale: locale)
        return String(localized: "\(weight) × \(fat), both logged that day")
    }

    @ViewBuilder
    private func row(label: String, value: String?, date: Date?, caption: String?, isDerived: Bool) -> some View {
        let valueText = value ?? ProgressV2Format.dash
        let dateText = date.map { ProgressV2Format.mediumDate($0, locale: locale, calendar: calendar, timeZone: timeZone) }
            ?? String(localized: "No readings")
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))

        layout {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(label)
                        .font(.system(.caption, weight: .heavy))
                        .fontWidth(.condensed)
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(IronTheme.textSecondary)
                    if isDerived {
                        Text("Derived")
                            .font(.system(.caption2, weight: .heavy))
                            .fontWidth(.condensed)
                            .textCase(.uppercase)
                            .foregroundStyle(IronTheme.canvas)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(IronTheme.brass, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                    }
                }
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(IronTheme.textTertiary)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(IronTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? CGFloat.infinity : nil, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }

            Text(valueText)
                .font(.system(.title3, weight: .bold).monospacedDigit())
                .foregroundStyle(value == nil ? IronTheme.textTertiary : IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(IronTheme.surfaceRaised)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDerived ? String(localized: "\(label), derived") : label)
        .accessibilityValue([valueText, dateText, caption].compactMap { $0 }.joined(separator: ", "))
    }
}
