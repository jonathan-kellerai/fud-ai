import SwiftUI

/// One challenge: ring, status, tiles, pace chart or day grid, log button, rewards.
/// Every number comes from `ChallengeProgress` via `ChallengePresentation`.
struct ChallengeDetailView: View {
    let challengeID: UUID
    @Environment(ChallengeStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @State private var showingQuickAdd = false
    @State private var confirmingEnd = false
    @ScaledMetric(relativeTo: .title) private var ringSide: CGFloat = 96

    private let tileColumns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if let challenge = store.challenge(id: challengeID) {
                content(challenge, progress: store.progress(for: challengeID))
            } else {
                Text("This challenge is gone.")
                    .foregroundStyle(IronTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(IronTheme.canvas)
        .navigationTitle("Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingQuickAdd) {
            ChallengeQuickAddSheet(challengeID: challengeID)
        }
        .task {
            await ChallengeMetricProviders.refreshSteps(store, healthKit: healthKit)
        }
    }

    private func content(_ challenge: Challenge, progress: ChallengeProgress?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(challenge, progress: progress)
                if let progress {
                    statusMessage(challenge, progress: progress)
                    let tiles = ChallengePresentation.tiles(challenge, progress)
                    if !tiles.isEmpty {
                        LazyVGrid(columns: tileColumns, spacing: 12) {
                            ForEach(tiles, id: \.label) { tile in
                                IronStatTile(label: tile.label, value: tile.value, detail: tile.detail)
                            }
                        }
                    }
                    if progress.status != .noData, progress.status != .invalid, progress.status != .notStarted {
                        if challenge.kind.isHabit {
                            ChallengeDayGrid(progress: progress)
                        } else {
                            ChallengePaceChart(progress: progress)
                        }
                    }
                }
                if ChallengePresentation.acceptsLogs(challenge, status: progress?.status, today: today) {
                    Button {
                        showingQuickAdd = true
                    } label: {
                        Text(challenge.isCheckIn ? "Check in" : "Log")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(IronPrimaryButtonStyle())
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("challenge.detail.log")
                    .challengeHitAnchor("challenge.detail.log")
                }
                rewards(challenge)
                if let stake = challenge.stake {
                    stakeRow(challenge, stake: stake)
                }
                settings(challenge, progress: progress)
            }
            .padding(16)
        }
        .settingsFloatingTabClearance()
        .confirmationDialog("End this challenge early?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End challenge", role: .destructive) { store.endEarly(challengeID) }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Rewards already unlocked stay unlocked.")
        }
    }

    private func header(_ challenge: Challenge, progress: ChallengeProgress?) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                ChallengeRing(fraction: progress?.fraction ?? 0)
                Text(ChallengePresentation.percent(progress?.fraction ?? 0))
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .fontWidth(.condensed)
                    .foregroundStyle(IronTheme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(12)
            }
            .frame(width: ringSide, height: ringSide)
            VStack(alignment: .leading, spacing: 6) {
                Text(challenge.title)
                    .font(.title2.weight(.heavy))
                    .fontWidth(.condensed)
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ChallengePresentation.goalSummary(challenge))
                    .font(.subheadline)
                    .foregroundStyle(IronTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress {
                    HStack(spacing: 8) {
                        IronStatusPill(
                            text: ChallengePresentation.statusLabel(progress.status, metric: challenge.metric),
                            tone: IronStatusPill.Tone(progress.status)
                        )
                        Text(ChallengePresentation.dayLabel(
                            progress, challenge: challenge, now: store.evaluatedAt ?? Date(), calendar: store.calendar
                        ))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(IronTheme.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .ironCard(rule: true)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusMessage(_ challenge: Challenge, progress: ChallengeProgress) -> some View {
        switch progress.status {
        case .noData:
            message(challenge.metric == .steps
                ? "No step data. Allow Health to share steps with JL Physical in Settings, then come back."
                : "No data yet.")
        case .invalid:
            message("Can't evaluate this challenge. Its saved target or length is out of range.")
        default:
            EmptyView()
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(IronTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .ironCard()
    }

    private func rewards(_ challenge: Challenge) -> some View {
        let unlocked = Dictionary(
            store.rewards(for: challenge.id).map { ($0.rewardKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return VStack(alignment: .leading, spacing: 8) {
            IronSectionTitle(title: "Rewards")
            ForEach(challenge.rewards, id: \.trigger.key) { reward in
                let record = unlocked[reward.trigger.key]
                HStack(spacing: 12) {
                    Image(systemName: record == nil ? "lock.fill" : "trophy.fill")
                        .foregroundStyle(record == nil ? IronTheme.textTertiary : IronTheme.brass)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(reward.title)
                        .foregroundStyle(record == nil ? IronTheme.textSecondary : IronTheme.textPrimary)
                    Spacer(minLength: 8)
                    if let record {
                        if record.claimedAt == nil {
                            Button("Claim") {
                                store.claim(rewardKey: reward.trigger.key, for: challenge.id)
                            }
                            .buttonStyle(IronCompactButtonStyle())
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                            .accessibilityIdentifier("reward.claim")
                        } else {
                            IronStatusPill(text: "Claimed", tone: .brass)
                        }
                    }
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
            NavigationLink {
                RewardLogView(challengeID: challenge.id)
            } label: {
                HStack {
                    Text("Reward log")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                }
                .foregroundStyle(IronTheme.bloodText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .padding(16)
        .ironCard()
    }

    private func stakeRow(_ challenge: Challenge, stake: ChallengeStake) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                IronSectionTitle(title: "Stake")
                Text(stake.text)
                    .foregroundStyle(IronTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if store.stakePaidAt[challenge.id] == nil {
                Button("Mark paid") { store.markStakePaid(challenge.id) }
                    .buttonStyle(IronCompactButtonStyle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            } else {
                IronStatusPill(text: "Paid", tone: .olive)
            }
        }
        .padding(16)
        .ironCard()
    }

    @ViewBuilder
    private func settings(_ challenge: Challenge, progress: ChallengeProgress?) -> some View {
        let active = progress?.status.isActive == true || progress?.status == .notStarted
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Remind me at 7 PM when behind", isOn: Binding(
                get: { challenge.reminder.enabled },
                set: { on in
                    var reminder = challenge.reminder
                    reminder.enabled = on
                    store.updateReminder(reminder, for: challenge.id)
                }
            ))
            .tint(IronTheme.blood)
            .frame(minHeight: 44)
            if active, challenge.endedEarlyAt == nil {
                Button("End challenge early", role: .destructive) { confirmingEnd = true }
                    .foregroundStyle(IronTheme.bloodText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(16)
        .ironCard()
    }

    private var today: ChallengeDay {
        ChallengeDay(store.evaluatedAt ?? Date(), calendar: store.calendar)
    }
}
