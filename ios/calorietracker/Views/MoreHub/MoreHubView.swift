import SwiftUI

/// The More hub list: rows only. `ProfileView` owns the sheets and destinations.
struct MoreHubView: View {
    let inputs: MoreHubInputs

    var body: some View {
        List {
            Section {
                // One row for the whole peptide area so the hub keeps seven rows on iPhone SE.
                // Recon Bench opens from the Peptides screen.
                NavigationLink {
                    PeptidesView()
                } label: {
                    SettingsHubRowLabel(
                        title: "Peptides",
                        systemImage: "cross.vial.fill",
                        subtitle: "Log, vials, Recon Bench"
                    )
                }
                .accessibilityIdentifier("settings.category.peptides")
                .overlay {
                    SettingsHubRowAnchor(identifier: "settings.category.peptides")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
            .listRowBackground(AppColors.appCard)

            Section {
                ForEach(ProfileSettingsCategory.preferenceCases) { category in
                    ProfileSettingsCategoryRow(category: category, subtitle: MoreHubSubtitles.text(for: category, inputs))
                }
            } header: {
                IronSectionTitle(title: "Settings")
            }
            .listRowBackground(AppColors.appCard)

            Section {
                ForEach(ProfileSettingsCategory.appInfoCases) { category in
                    ProfileSettingsCategoryRow(category: category, subtitle: MoreHubSubtitles.text(for: category, inputs))
                }
            } header: {
                IronSectionTitle(title: "App")
            }
            .listRowBackground(AppColors.appCard)

        }
        .listSectionSpacing(4)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(AppColors.appBackground)
        .settingsFloatingTabClearance()
        .toolbar(.hidden, for: .navigationBar)
    }
}
