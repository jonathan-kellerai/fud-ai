import SwiftUI

/// Settings: the one-time result of deleting an upstream Weekly Challenge profile.
struct WeeklyChallengeAutoDeleteSection: View {
    let outcome: WeeklyChallengeAutoDelete.Outcome

    var body: some View {
        Section {
            Label {
                Text(WeeklyChallengeAutoDelete.statusLine(outcome))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: outcome.result == .failed ? "exclamationmark.triangle" : "checkmark.shield")
                    .foregroundStyle(AppColors.calorie)
            }
            .accessibilityElement(children: .combine)
        } header: {
            IronSectionTitle(title: "Weekly Challenge")
        }
        .listRowBackground(AppColors.appCard)
    }
}
