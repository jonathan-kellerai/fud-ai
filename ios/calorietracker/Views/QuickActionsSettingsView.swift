import SwiftUI

struct QuickActionsSettingsView: View {
    var embedsInParentList = false
    @AppStorage(QuickActionSettings.storageKeys[0]) private var firstRaw = QuickActionSettings.defaults[0].rawValue
    @AppStorage(QuickActionSettings.storageKeys[1]) private var secondRaw = QuickActionSettings.defaults[1].rawValue
    @AppStorage(QuickActionSettings.storageKeys[2]) private var thirdRaw = QuickActionSettings.defaults[2].rawValue

    var body: some View {
        if embedsInParentList {
            shortcutSection
                .onChange(of: firstRaw) { _, _ in refreshShortcuts() }
                .onChange(of: secondRaw) { _, _ in refreshShortcuts() }
                .onChange(of: thirdRaw) { _, _ in refreshShortcuts() }
        } else {
            Form {
                shortcutSection
            }
            .navigationTitle("Shortcuts & Siri")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: firstRaw) { _, _ in refreshShortcuts() }
            .onChange(of: secondRaw) { _, _ in refreshShortcuts() }
            .onChange(of: thirdRaw) { _, _ in refreshShortcuts() }
        }
    }

    private var shortcutSection: some View {
        Section {
            quickActionPicker(title: "App Icon Shortcut 1", selection: $firstRaw)
            quickActionPicker(title: "App Icon Shortcut 2", selection: $secondRaw)
            quickActionPicker(title: "App Icon Shortcut 3", selection: $thirdRaw)
        } header: {
            Text("App Icon Shortcuts")
        } footer: {
            Text("Hold the JL Physical app icon to use these shortcuts. Each slot opens its selected action directly. On iPhone, App Icon Shortcut 1–3 can also be assigned in Shortcuts to the Action Button or Back Tap.")
        }
    }

    private func quickActionPicker(title: String, selection: Binding<String>) -> some View {
        Picker(selection: selection) {
            ForEach(QuickAction.allCases) { action in
                Label(action.title, systemImage: action.systemImageName)
                    .tag(action.rawValue)
            }
        } label: {
            Label(title, systemImage: numberIcon(for: title))
        }
        .pickerStyle(.menu)
        .tint(.secondary)
    }

    private func numberIcon(for title: String) -> String {
        title.hasSuffix("1") ? "1.circle.fill" : title.hasSuffix("2") ? "2.circle.fill" : "3.circle.fill"
    }

    private func refreshShortcuts() {
        QuickActionSettings.registerApplicationShortcuts()
    }
}
