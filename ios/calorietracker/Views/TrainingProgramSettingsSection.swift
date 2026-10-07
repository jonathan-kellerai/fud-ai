import SwiftUI

/// More › Training's "Program" section: the program library, the exercise
/// library and the workouts saved on this phone. ProfileView owns the
/// exercise library sheet.
struct TrainingProgramSettingsSection: View {
    let onExerciseLibrary: () -> Void

    var body: some View {
        Section {
            NavigationLink {
                ProgramLibraryView()
            } label: {
                SettingsHubRowLabel(
                    title: "Programs",
                    systemImage: "list.bullet",
                    subtitle: ActiveProgramCache.load()?.name ?? "Program V2"
                )
            }
            Button {
                onExerciseLibrary()
            } label: {
                HStack {
                    SettingsHubRowLabel(
                        title: "Exercise Library",
                        systemImage: "dumbbell.fill",
                        subtitle: "Browse movements"
                    )
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(IronTheme.textPrimary)
            NavigationLink {
                WorkoutsSettingsView()
            } label: {
                SettingsHubRowLabel(
                    title: "Workouts",
                    systemImage: "clock.arrow.circlepath",
                    subtitle: "History, import from a file"
                )
            }
            .accessibilityIdentifier("settings.training.workouts")
        } header: {
            IronSectionTitle(title: "Program")
        }
        .listRowBackground(AppColors.appCard)
    }
}
