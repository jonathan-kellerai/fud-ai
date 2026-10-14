import SwiftUI

// MARK: - Siri Phrases
struct SiriPhrasesSettingsView: View {
    private let groups: [SiriPhraseGroup] = [
        SiriPhraseGroup(
            title: "Log Food",
            icon: "fork.knife",
            phrases: [
                "Log food in JL Physical",
                "Add food in JL Physical",
                "Track food in JL Physical",
            ]
        ),
        SiriPhraseGroup(
            title: "Today's Calories",
            icon: "chart.bar.fill",
            phrases: [
                "Calories today in JL Physical",
                "How many calories in JL Physical",
                "Today's nutrition in JL Physical",
            ]
        ),
        SiriPhraseGroup(
            title: "Log Weight",
            icon: "scalemass.fill",
            phrases: [
                "Log my weight in JL Physical",
                "Record weight in JL Physical",
            ]
        ),
    ]

    var body: some View {
        List {
            Section {
                Label {
                    Text("Say these phrases to Siri to use JL Physical hands-free.")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(AppColors.calorie)
                }
            }
            .listRowBackground(AppColors.appCard)

            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.phrases, id: \.self) { phrase in
                        Text("Hey Siri, \(phrase)")
                            .foregroundStyle(.primary)
                    }
                }
                .listRowBackground(AppColors.appCard)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .navigationTitle("Siri Phrases")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SiriPhraseGroup: Identifiable {
    let title: String
    let icon: String
    let phrases: [String]

    var id: String { title }
}
