import SwiftUI

/// Shown once per unlock. Fades in (no scale under Reduce Motion) with a success haptic.
struct RewardUnlockedView: View {
    let unlock: RewardUnlock
    let challengeTitle: String
    var onClaim: () -> Void
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(IronTheme.brass)
                    .accessibilityHidden(true)
                IronSectionTitle(title: "Reward unlocked")
                    .multilineTextAlignment(.center)
                Text(unlock.title)
                    .font(.largeTitle.weight(.black))
                    .fontWidth(.condensed)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(challengeTitle)
                    .font(.headline)
                    .foregroundStyle(IronTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Button {
                    onClaim()
                } label: {
                    Text("Claim").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(IronPrimaryButtonStyle())
                .accessibilityIdentifier("reward.claim")
                .challengeHitAnchor("reward.claim")
                Button("Later") { onDone() }
                    .foregroundStyle(IronTheme.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("reward.later")
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
        }
        .background(IronTheme.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reward unlocked: \(unlock.title), \(challengeTitle).")
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(IronTheme.motion) { appeared = true }
        }
    }
}

/// Every unlocked reward for one challenge, with claim and stake state.
struct RewardLogView: View {
    let challengeID: UUID
    @Environment(ChallengeStore.self) private var store

    var body: some View {
        List {
            let records = store.rewards(for: challengeID).sorted { $0.unlockedAt > $1.unlockedAt }
            Section {
                if records.isEmpty {
                    Text("No rewards yet.")
                        .foregroundStyle(IronTheme.textSecondary)
                }
                ForEach(records, id: \.rewardKey) { record in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.title).foregroundStyle(IronTheme.textPrimary)
                            Text("Unlocked \(record.unlockedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.footnote)
                                .foregroundStyle(IronTheme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        if record.claimedAt == nil {
                            Button("Claim") { store.claim(rewardKey: record.rewardKey, for: challengeID) }
                                .buttonStyle(IronCompactButtonStyle())
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        } else {
                            IronStatusPill(text: "Claimed", tone: .brass)
                        }
                    }
                    .frame(minHeight: 44)
                }
            } header: {
                IronSectionTitle(title: "Unlocked")
            }
            .listRowBackground(IronTheme.surface)

            if let stake = store.challenge(id: challengeID)?.stake {
                Section {
                    HStack {
                        Text(stake.text).foregroundStyle(IronTheme.textPrimary)
                        Spacer(minLength: 8)
                        if let paid = store.stakePaidAt[challengeID] {
                            Text("Paid \(paid.formatted(date: .abbreviated, time: .omitted))")
                                .font(.footnote)
                                .foregroundStyle(IronTheme.olive)
                        } else {
                            Button("Mark paid") { store.markStakePaid(challengeID) }
                                .buttonStyle(IronCompactButtonStyle())
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                    }
                } header: {
                    IronSectionTitle(title: "Stake")
                }
                .listRowBackground(IronTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(IronTheme.canvas)
        .navigationTitle("Reward Log")
        .navigationBarTitleDisplayMode(.inline)
        .settingsFloatingTabClearance()
    }
}
