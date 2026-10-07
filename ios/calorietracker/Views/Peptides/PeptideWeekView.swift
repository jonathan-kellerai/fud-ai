//
//  PeptideWeekView.swift
//  calorietracker
//
//  Peptides › Week: seven day cells per compound, draws as typed (units or
//  mL), a dash for an empty day. At accessibility text sizes, or when seven
//  cells don't fit, each compound becomes a stacked day list. Then the week's
//  history and the optional schedule row. No targets, no streak advice, no mg.
//

import SwiftUI

struct PeptideWeekView: View {
    @Environment(PeptideLogStore.self) private var store
    /// yyyy-MM-dd, America/New_York.
    let today: String
    let referenceDate: Date?
    @State private var weekStart: String? = nil

    private var shownWeek: String { weekStart ?? ReconMath.mondayOf(today) }

    var body: some View {
        let rows = PeptideMath.weekRows(entries: store.entries, weekStart: shownWeek)
        VStack(alignment: .leading, spacing: 12) {
            weekHeader
            if rows.isEmpty {
                Text("No draws logged this week.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(IronTheme.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .peptideAccentCard(IronTheme.concrete)
            }
            ForEach(rows) { row in
                PeptideWeekRowCard(row: row)
            }
            Text("Days with no record show a dash. No targets, no streak advice.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PeptideHistoryView(from: shownWeek, to: ReconMath.addDays(shownWeek, 6))
            scheduleRow
        }
    }

    private var weekHeader: some View {
        let isCurrent = shownWeek == ReconMath.mondayOf(today)
        return HStack(alignment: .center, spacing: 8) {
            Button {
                weekStart = ReconMath.addDays(shownWeek, -7)
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(IronTheme.brass)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous week")
            PeptideHeader(text: PeptideMath.weekTitle(shownWeek))
            Button {
                weekStart = ReconMath.addDays(shownWeek, 7)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(isCurrent ? IronTheme.textTertiary : IronTheme.brass)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isCurrent)
            .accessibilityLabel("Next week")
        }
    }

    private var scheduleRow: some View {
        let active = store.schedules.filter(\.active).count
        return NavigationLink {
            PeptideScheduleView(referenceDate: referenceDate)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Schedule (optional)")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(IronTheme.textPrimary)
                    Text(active == 0 ? "None set. You type any schedule yourself." : (active == 1 ? "1 schedule" : "\(active) schedules"))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .foregroundStyle(IronTheme.brass)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .peptideAccentCard(IronTheme.concrete)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One compound's week: a 7-cell grid, or a stacked day list when the grid
/// can't fit (large text, iPhone SE). Every cell reads as one VoiceOver line.
struct PeptideWeekRowCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let row: PeptideMath.WeekRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.compound)
                .font(.system(.title3, design: .default, weight: .black))
                .fontWidth(.condensed)
                .foregroundStyle(IronTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if dynamicTypeSize.isAccessibilitySize {
                stacked
            } else {
                ViewThatFits(in: .horizontal) {
                    grid
                    stacked
                }
            }
            Text(row.drawCount == 1 ? "1 draw logged, as entered." : "\(row.drawCount) draws logged, as entered.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(IronTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .peptideAccentCard(IronTheme.olive)
    }

    private var grid: some View {
        HStack(spacing: 4) {
            ForEach(row.cells) { cell in
                VStack(spacing: 4) {
                    Text(cell.letter)
                        .font(.system(.caption, design: .default, weight: .heavy))
                        .fontWidth(.condensed)
                        .foregroundStyle(IronTheme.brass)
                    Text(cell.shortText)
                        .font(.system(.caption, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(cell.hasRecord ? IronTheme.textPrimary : IronTheme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(IronTheme.canvas, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                        .stroke(cell.hasRecord ? IronTheme.olive : IronTheme.hairline, lineWidth: 1)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(cell.spoken)
            }
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(row.cells) { cell in
                Text(cell.shortDay + ": " + cell.longText)
                    .font(.system(.body, design: .rounded, weight: cell.hasRecord ? .semibold : .regular))
                    .foregroundStyle(cell.hasRecord ? IronTheme.textPrimary : IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(cell.spoken)
            }
        }
    }
}
