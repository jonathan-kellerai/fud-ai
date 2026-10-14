//
//  ChangeWorkoutSheet.swift
//  calorietracker
//
//  Picks a different program day for today. The rows, the "Suggested" day,
//  and what a pick means for today's override all come from the schedule.
//

import SwiftUI

struct ChangeWorkoutSheet: View {
    let options: [TrainingWorkoutOption]
    /// The cycle's day, tagged "Suggested".
    let suggestedDayIndex: Int?
    /// The day the Train card shows now, checked.
    let currentDayIndex: Int?
    let isChanged: Bool
    let onPick: (Int) -> Void
    let onBackToSuggested: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if isChanged {
                    Section {
                        Button {
                            onBackToSuggested()
                            dismiss()
                        } label: {
                            Label("Back to suggested", systemImage: "arrow.uturn.backward")
                                .font(.headline)
                                .foregroundStyle(IronTheme.bloodText)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("changeWorkout.backToSuggested")
                        .listRowBackground(IronTheme.surface)
                    }
                }
                Section {
                    ForEach(options) { option in
                        let suggested = option.dayIndex == suggestedDayIndex
                        let selected = option.dayIndex == currentDayIndex
                        Button {
                            onPick(option.dayIndex)
                            dismiss()
                        } label: {
                            row(option, suggested: suggested, selected: selected)
                        }
                        .accessibilityLabel(option.accessibilityLabel(suggested: suggested, selected: selected))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("changeWorkout.day.\(option.dayIndex)")
                        .listRowBackground(IronTheme.surface)
                    }
                } header: {
                    IronSectionTitle(title: "Program days")
                }
            }
            .scrollContentBackground(.hidden)
            .background(IronTheme.canvas)
            .navigationTitle("Change Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func row(_ option: TrainingWorkoutOption, suggested: Bool, selected: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.title)
                    .font(.headline)
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(option.detail)
                    .font(.subheadline)
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if suggested {
                    Text("Suggested")
                        .font(.caption.weight(.heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(IronTheme.brass)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            IronTheme.brass.opacity(IronTheme.pillFillOpacity),
                            in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                        )
                }
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "checkmark")
                    .font(.headline)
                    .foregroundStyle(IronTheme.bloodText)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
