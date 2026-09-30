import SwiftUI

struct ShortcutsAndSiriSettingsView: View {
    var body: some View {
        List {
            QuickActionsSettingsView(embedsInParentList: true)
            SiriPhraseSections()
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .settingsFloatingTabClearance()
        .navigationTitle("Shortcuts & Siri")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SiriPhraseSections: View {
    private let groups: [(title: String, phrases: [String])] = [
        ("Log Food", [
            "Log food in JL Physical",
            "Add food in JL Physical",
            "Track food in JL Physical",
        ]),
        ("Today's Calories", [
            "Calories today in JL Physical",
            "How many calories in JL Physical",
            "Today's nutrition in JL Physical",
        ]),
        ("Log Weight", [
            "Log my weight in JL Physical",
            "Record weight in JL Physical",
        ]),
    ]

    var body: some View {
        Group {
            Section {
                Text("Say these phrases to Siri to use JL Physical hands-free.")
                    .foregroundStyle(.secondary)
            } header: {
                IronSectionTitle(title: "Siri Phrases")
            }
            .listRowBackground(AppColors.appCard)

            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.phrases, id: \.self) { phrase in
                        Text("Hey Siri, \(phrase)")
                    }
                }
                .listRowBackground(AppColors.appCard)
            }
        }
    }
}
