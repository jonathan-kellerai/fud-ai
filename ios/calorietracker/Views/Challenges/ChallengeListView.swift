import SwiftUI

/// Challenges home: active first, then finished. Opened from the More hub.
struct ChallengeListView: View {
    @Environment(ChallengeStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @State private var showingCreate = false
    /// Rewards pop up here only while this list is on screen; the quick-add sheet shows its own.
    @State private var isVisible = false

    private var now: Date { store.evaluatedAt ?? Date() }

    private var active: [Challenge] { store.activeChallenges }

    private var finished: [Challenge] {
        let activeIDs = Set(active.map(\.id))
        return store.challenges
            .filter { !activeIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if store.challenges.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Set a goal with a deadline: a total, a daily average or a daily habit. Progress, pace and rewards stay on this iPhone.")
                            .font(.subheadline)
                            .foregroundStyle(IronTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Start a challenge") { showingCreate = true }
                            .buttonStyle(IronPrimaryButtonStyle())
                            .accessibilityIdentifier("challenges.empty.create")
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(IronTheme.surface)
            }
            if !active.isEmpty {
                Section {
                    rows(active, offset: 0)
                } header: {
                    IronSectionTitle(title: "Active")
                }
                .listRowBackground(IronTheme.surface)
            }
            if !finished.isEmpty {
                Section {
                    rows(finished, offset: active.count)
                } header: {
                    IronSectionTitle(title: "Finished")
                }
                .listRowBackground(IronTheme.surface)
            }
        }
        .accessibilityIdentifier("challenges.list")
        .scrollContentBackground(.hidden)
        .background(IronTheme.canvas)
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("New challenge")
                .accessibilityIdentifier("challenges.create")
            }
        }
        .settingsFloatingTabClearance()
        .sheet(isPresented: $showingCreate) {
            ChallengeCreateView()
        }
        .sheet(isPresented: rewardPresented) {
            if let unlock = store.pendingUnlocks.first {
                RewardUnlockedView(
                    unlock: unlock,
                    challengeTitle: store.challenge(id: unlock.challengeID)?.title ?? "",
                    onClaim: {
                        store.claim(rewardKey: unlock.rewardKey, for: unlock.challengeID)
                        store.acknowledge(unlock)
                    },
                    onDone: { store.acknowledge(unlock) }
                )
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task {
            await ChallengeMetricProviders.refreshSteps(store, healthKit: healthKit)
        }
    }

    private var rewardPresented: Binding<Bool> {
        Binding(
            get: { isVisible && !showingCreate && !store.pendingUnlocks.isEmpty },
            set: { presented in
                if !presented, let unlock = store.pendingUnlocks.first { store.acknowledge(unlock) }
            }
        )
    }

    @ViewBuilder
    private func rows(_ challenges: [Challenge], offset: Int) -> some View {
        ForEach(Array(challenges.enumerated()), id: \.element.id) { index, challenge in
            NavigationLink {
                ChallengeDetailView(challengeID: challenge.id)
            } label: {
                ChallengeSummaryRow(
                    challenge: challenge,
                    progress: store.progress(for: challenge.id),
                    now: now,
                    calendar: store.calendar
                )
            }
            .accessibilityIdentifier("challenges.row.\(offset + index)")
        }
    }
}
