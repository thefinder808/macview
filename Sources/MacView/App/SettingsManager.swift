import Foundation
import Combine

/// Thin UserDefaults wrapper for the few user preferences MacView has. Singleton
/// so the menu, Settings scene, and ViewerModel all read one source of truth.
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var confirmBeforeDelete: Bool {
        didSet { defaults.set(confirmBeforeDelete, forKey: Keys.confirmBeforeDelete) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let confirmBeforeDelete = "confirmBeforeDelete"
    }

    private init() {
        // Default the confirm prompt ON (safe) when never set.
        if defaults.object(forKey: Keys.confirmBeforeDelete) == nil {
            defaults.set(true, forKey: Keys.confirmBeforeDelete)
        }
        confirmBeforeDelete = defaults.bool(forKey: Keys.confirmBeforeDelete)
    }
}
