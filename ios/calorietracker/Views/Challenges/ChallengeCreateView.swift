import SwiftUI

/// New challenge form. `ChallengeDraft` owns validation and building.
struct ChallengeCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @State private var draft: ChallengeDraft
    @State private var errorText: String?

    init(draft: ChallengeDraft = ChallengeDraft()) {
        _draft = State(initialValue: draft)
    }

    private var candidate: Challenge? {
        draft.build(now: Date(), calendar: store.calendar)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. 10K KB swings", text: $draft.title)
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("challenges.create.title")
                } header: {
                    IronSectionTitle(title: "Challenge")
                }
                .listRowBackground(IronTheme.surface)

                Section {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(ChallengeDraft.Kind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    Picker("Measure", selection: $draft.metric) {
                        ForEach(ChallengeDraft.MetricChoice.allCases, id: \.self) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    if draft.metric == .custom {
                        TextField("What you count, e.g. KB swings", text: $draft.customName)
                        TextField("Unit, e.g. reps", text: $draft.customUnit)
                            .textInputAutocapitalization(.never)
                    }
                    if draft.kind == .dailyHabit {
                        Picker("Rule", selection: $draft.habit) {
                            ForEach(ChallengeDraft.HabitChoice.allCases, id: \.self) { habit in
                                Text(habit.title).tag(habit)
                            }
                        }
                    }
                    if draft.needsTarget {
                        TextField(targetPrompt, text: $draft.targetText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("challenges.create.target")
                    }
                } header: {
                    IronSectionTitle(title: "Goal")
                } footer: {
                    if draft.metric == .steps {
                        Text("Steps come from Apple Health. If Health can't be read, the challenge shows No step data instead of zero.")
                    } else if draft.metric == .water {
                        Text("Water counts what you log in this app.")
                    }
                }
                .listRowBackground(IronTheme.surface)

                Section {
                    Stepper(value: durationBinding, in: ChallengeRules.durationRange) {
                        AdaptiveLabelValue {
                            Text("Length")
                        } value: {
                            Text("\(draft.durationDays) days").monospacedDigit()
                        }
                    }
                    if draft.kind == .dailyHabit {
                        Stepper(value: $draft.graceDays, in: 0...max(0, draft.durationDays - 1)) {
                            AdaptiveLabelValue {
                                Text("Grace days")
                            } value: {
                                Text("\(draft.graceDays)").monospacedDigit()
                            }
                        }
                    }
                    Toggle("Remind me at 7 PM when behind", isOn: $draft.remindersOn)
                        .tint(IronTheme.blood)
                } header: {
                    IronSectionTitle(title: "Schedule")
                } footer: {
                    Text("Starts today. Reminders only fire when the challenge is behind and Notifications are on.")
                }
                .listRowBackground(IronTheme.surface)

                Section {
                    TextField("Optional, e.g. $20 to Sam", text: $draft.stakeText)
                } header: {
                    IronSectionTitle(title: "Stake")
                }
                .listRowBackground(IronTheme.surface)

                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(IronTheme.bloodText)
                    }
                    .listRowBackground(IronTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(IronTheme.canvas)
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(candidate == nil)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("challenges.create.save")
                }
            }
        }
    }

    private var targetPrompt: String {
        switch draft.kind {
        case .total: "Target total"
        case .dailyAverage: "Target per day"
        case .dailyHabit: draft.metric == .water ? "Litres per day" : "Amount per day"
        }
    }

    private var durationBinding: Binding<Int> {
        Binding(get: { draft.durationDays }, set: { draft.setDuration($0) })
    }

    private func save() {
        guard let challenge = candidate else { return }
        do {
            try store.create(challenge)
            dismiss()
        } catch {
            errorText = "Couldn't save this challenge. Check the target and length."
        }
    }
}
