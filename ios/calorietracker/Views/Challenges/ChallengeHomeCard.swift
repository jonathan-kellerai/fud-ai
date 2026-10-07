import SwiftUI

/// Home rows for up to two running challenges. Each row opens the challenge.
struct ChallengeHomeCard: View {
    let store: ChallengeStore

    var body: some View {
        ForEach(Array(store.activeChallenges.prefix(2))) { challenge in
            NavigationLink {
                ChallengeDetailView(challengeID: challenge.id)
            } label: {
                ChallengeSummaryRow(
                    challenge: challenge,
                    progress: store.progress(for: challenge.id),
                    now: store.evaluatedAt ?? Date(),
                    calendar: store.calendar
                )
            }
            .listRowBackground(IronTheme.surface)
            .accessibilityIdentifier("home.card.challenges")
        }
    }
}
