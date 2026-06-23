import SwiftUI

/// The single Settings pane (⌘,). Minimal by design.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Form {
            Toggle("Confirm before moving to Trash", isOn: $settings.confirmBeforeDelete)
        }
        .padding(20)
        .frame(width: 380)
    }
}
