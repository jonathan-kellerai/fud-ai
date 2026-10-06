import SwiftUI

struct CloudBackupSettingsSection: View {
    @Environment(CloudBackupService.self) private var backup
    @State private var showEnableConfirm = false
    @State private var showRestoreChoice = false
    @State private var showBackupActions = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { backup.enabled },
                set: { on in
                    if on { showEnableConfirm = true }
                    else { backup.enabled = false }
                }
            )) {
                Label("iCloud Backup", systemImage: "icloud")
            }
            .accessibilityIdentifier("settings.cloudBackup.toggle")
            .disabled(backup.busy)

            if let last = backup.lastAt {
                (Text("Last backup: ") + Text(shortDate(last)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings.cloudBackup.lastBackup")
            }

            if backup.enabled {
                Button("Back Up Now") { Task { await run { try await backup.backupNow() } } }
                    .accessibilityIdentifier("settings.cloudBackup.backupNow")
                    .disabled(backup.busy)
                Button("Restore or Delete Backup…") { showBackupActions = true }
                    .disabled(backup.busy)
            }
        } header: {
            IronSectionTitle(title: "iCloud")
        } footer: {
            Text("Backups stay off until you turn this on. Uses the iCloud account on this iPhone — change Apple ID in iOS Settings if you need a different account. API keys stay on the device.")
        }
        .listRowBackground(AppColors.appCard)
        .alert("iCloud Backup", isPresented: $showEnableConfirm) {
            Button("Turn On") {
                Task { await turnOn() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Uploads your diary, workouts, fasting, photos, and settings to your iCloud. API keys stay on the phone.")
        }
        .alert("Restore backup?", isPresented: $showRestoreChoice) {
            Button("Restore") {
                Task { await run { try await backup.restoreNow() } }
            }
            Button("Keep this phone") {
                Task { await run { try await backup.backupNow() } }
            }
        } message: {
            Text("Restore it, or keep this phone.")
        }
        .confirmationDialog("Restore or Delete Backup?", isPresented: $showBackupActions, titleVisibility: .visible) {
            Button("Restore") {
                Task { await run { try await backup.restoreNow() } }
            }
            .accessibilityIdentifier("settings.cloudBackup.restoreNow")
            Button("Delete", role: .destructive) {
                Task { await run { try await backup.deleteCloudBackup() } }
            }
            .accessibilityIdentifier("settings.cloudBackup.delete")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore replaces this phone with the iCloud backup. Delete removes the JL Physical file from iCloud and leaves this phone unchanged.")
        }
        .alert("iCloud Backup", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func turnOn() async {
        do {
            try await backup.checkAccount()
            await backup.refreshCloudPresence()
            if backup.hasCloudBackup {
                showRestoreChoice = true
            } else {
                try await backup.backupNow()
            }
        } catch {
            backup.enabled = false
            errorMessage = error.localizedDescription
        }
    }

    private func run(_ work: () async throws -> Void) async {
        do {
            try await work()
            // A restore that went through but kept this phone's peptides says why.
            if let note = backup.errorMessage {
                errorMessage = note
                backup.errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shortDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
