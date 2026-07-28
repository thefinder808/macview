import SwiftUI

/// The Settings pane (⌘,). Minimal: the delete-confirm preference and a
/// one-click "make me the default image viewer".
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var updater: UpdaterService
    @State private var status: String?
    @State private var working = false

    var body: some View {
        // Sparkle's automaticallyChecksForUpdates is a plain get/set on the
        // updater controller (not @Published), so wrap it in a manual Binding.
        let autoCheck = Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

        Form {
            Section {
                Toggle("Confirm before moving to Trash", isOn: $settings.confirmBeforeDelete)
            }

            Section("Software Updates") {
                Toggle("Automatically check for updates", isOn: autoCheck)
                LabeledContent("You're on MacView \(version).") {
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }

            Section("Default Image Viewer") {
                Button {
                    working = true
                    Task {
                        let outcome = await DefaultViewer.makeDefault()
                        working = false
                        status = outcome.lastError == nil
                            ? "MacView is now the default for \(outcome.succeeded) image types."
                            : "Set \(outcome.succeeded) of \(outcome.total). \(outcome.lastError!.localizedDescription)"
                    }
                } label: {
                    Text("Set MacView as the Default Image Viewer")
                }
                .disabled(working)

                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Text("Tip: install MacView to /Applications first (so the association points at a stable location, not a build folder).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }
}
