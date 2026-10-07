import SwiftUI

/// Log an amount (chips or typed) or a YES/NO check-in for today or yesterday.
/// A logged amount can be undone for 5 seconds, also while a reward it unlocked is showing.
struct ChallengeQuickAddSheet: View {
    let challengeID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(ChallengeStore.self) private var store
    @State private var dayChoice: DayChoice = .today
    @State private var amountText = ""
    @State private var errorText: String?
    @State private var undoEntry: ChallengeEntry?
    @State private var undoToken = 0
    @ScaledMetric(relativeTo: .headline) private var chipHeight: CGFloat = 44

    enum DayChoice: String, CaseIterable, Hashable {
        case today
        case yesterday

        var title: String { self == .today ? "Today" : "Yesterday" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let unlock = store.pendingUnlocks.first(where: { $0.challengeID == challengeID }) {
                    RewardUnlockedView(
                        unlock: unlock,
                        challengeTitle: store.challenge(id: challengeID)?.title ?? "",
                        onClaim: {
                            store.claim(rewardKey: unlock.rewardKey, for: challengeID)
                            store.acknowledge(unlock)
                        },
                        onDone: { store.acknowledge(unlock) }
                    )
                } else if let challenge = store.challenge(id: challengeID) {
                    form(challenge)
                }
            }
            // Outside the reward/form switch so Undo stays reachable when the log unlocks a reward.
            .safeAreaInset(edge: .bottom) {
                if let undoEntry, let challenge = store.challenge(id: challengeID) {
                    undoBanner(undoEntry, challenge: challenge)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .background(IronTheme.canvas)
            .navigationTitle(store.challenge(id: challengeID)?.title ?? "Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func form(_ challenge: Challenge) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Day", selection: $dayChoice) {
                    ForEach(DayChoice.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: 44)

                if challenge.isCheckIn {
                    checkInButtons
                } else {
                    chips(challenge)
                    amountField(challenge)
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(IronTheme.bloodText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }

    private var checkInButtons: some View {
        HStack(spacing: 12) {
            Button {
                checkIn(true)
            } label: {
                Text("Yes").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(IronPrimaryButtonStyle())
            .accessibilityIdentifier("challenge.quickAdd.yes")
            .challengeHitAnchor("challenge.quickAdd.yes")
            Button {
                checkIn(false)
            } label: {
                Text("No").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(IronPrimaryButtonStyle(enabled: false))
            .accessibilityIdentifier("challenge.quickAdd.no")
            .challengeHitAnchor("challenge.quickAdd.no")
        }
    }

    private func chips(_ challenge: Challenge) -> some View {
        let columns = [GridItem(.adaptive(minimum: 88), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(Array(challenge.quickAddChips.enumerated()), id: \.offset) { index, amount in
                Button {
                    log(amount)
                } label: {
                    Text("+\(ChallengePresentation.amount(amount, metric: challenge.metric))")
                        .font(.headline.weight(.heavy).monospacedDigit())
                        .fontWidth(.condensed)
                        .foregroundStyle(IronTheme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: chipHeight)
                        .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous)
                                .strokeBorder(IronTheme.bloodText.opacity(IronTheme.borderTintOpacity), lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add \(ChallengePresentation.quantity(amount, metric: challenge.metric))")
                .accessibilityIdentifier("challenge.quickAdd.chip.\(index)")
                .challengeHitAnchor("challenge.quickAdd.chip.\(index)")
            }
        }
    }

    private func amountField(_ challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Amount (\(ChallengePresentation.unit(challenge.metric)))", text: $amountText)
                .keyboardType(.decimalPad)
                .padding(12)
                .frame(minHeight: 44)
                .background(IronTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: IronTheme.buttonRadius, style: .continuous))
                .accessibilityIdentifier("challenge.quickAdd.amount")
            Button {
                logTyped()
            } label: {
                Text("Log").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(IronPrimaryButtonStyle())
            .accessibilityIdentifier("challenge.quickAdd.log")
            .challengeHitAnchor("challenge.quickAdd.log")
        }
    }

    private func undoBanner(_ entry: ChallengeEntry, challenge: Challenge) -> some View {
        HStack(spacing: 12) {
            Text("Logged \(ChallengePresentation.quantity(entry.value, metric: challenge.metric))")
                .foregroundStyle(IronTheme.textPrimary)
            Spacer(minLength: 8)
            Button("Undo") {
                store.undo(entryID: entry.id)
                undoEntry = nil
            }
            .buttonStyle(IronCompactButtonStyle())
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityIdentifier("challenge.quickAdd.undo")
        }
        .padding(12)
        .ironCard()
    }

    // MARK: - Actions

    private var selectedDay: ChallengeDay {
        let today = ChallengeDay(Date(), calendar: store.calendar)
        return dayChoice == .today ? today : today.adding(days: -1)
    }

    private func logTyped() {
        let cleaned = amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let typed = Double(cleaned) else {
            errorText = "Enter an amount."
            return
        }
        guard let challenge = store.challenge(id: challengeID) else { return }
        // Water is typed in litres and stored in ml.
        log(challenge.metric == .waterAppLog ? typed * 1_000 : typed)
        if errorText == nil { amountText = "" }
    }

    private func log(_ amount: Double) {
        do {
            let entry = try store.add(value: amount, day: selectedDay, to: challengeID)
            errorText = nil
            showUndo(entry)
        } catch {
            errorText = Self.message(for: error)
        }
    }

    private func checkIn(_ value: Bool) {
        do {
            try store.setCheckIn(value, day: selectedDay, for: challengeID)
            errorText = nil
            dismiss()
        } catch {
            errorText = Self.message(for: error)
        }
    }

    private func showUndo(_ entry: ChallengeEntry) {
        undoEntry = entry
        undoToken += 1
        let token = undoToken
        Task {
            try? await Task.sleep(for: .seconds(5))
            if undoToken == token { undoEntry = nil }
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? ChallengeStoreError {
        case .outsideWindow: "That day is outside this challenge."
        case .invalidValue: "Enter an amount above zero."
        default: "Couldn't log that."
        }
    }
}
