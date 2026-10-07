//
//  PeptideSettingsView.swift
//  calorietracker
//
//  Peptides → Settings. One setting: the syringe scale the user draws with.
//  Each draw in units records the scale in force when it's saved.
//

import SwiftUI

struct PeptideSettingsView: View {
    @Environment(PeptideLogStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PeptideScreenTitle(title: "Peptide settings", subtitle: "Kept on this phone with your peptide log.")
                VStack(alignment: .leading, spacing: 10) {
                    IronSectionTitle(title: "Syringe scale")
                    Text("The units marked per mL on the syringes you use. A draw in units records the scale set here when you save it. Changing it later never changes a saved draw.")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(IronTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(PeptideSyringeScale.allCases) { scale in
                        scaleRow(
                            title: scale.label,
                            detail: "\(scale.rawValue) units = 1 mL",
                            selected: store.syringeScale == scale
                        ) {
                            store.setSyringeScale(scale)
                        }
                    }
                    scaleRow(
                        title: "Not set",
                        detail: "Draws in units show no mg",
                        selected: store.syringeScale == nil
                    ) {
                        store.setSyringeScale(nil)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("peptides.settings.syringeScale")
                if let error = store.persistError {
                    PeptideIssueText(text: error)
                }
                PeptideFooter()
            }
            .padding(16)
        }
        .background(IronTheme.canvas)
        .navigationTitle("Peptide settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scaleRow(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(IronTheme.textPrimary)
                    Text(detail)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(IronTheme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? IronTheme.brass : IronTheme.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(IronTheme.surface, in: RoundedRectangle(cornerRadius: IronTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: IronTheme.cardRadius, style: .continuous)
                    .stroke(selected ? IronTheme.brass : IronTheme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
