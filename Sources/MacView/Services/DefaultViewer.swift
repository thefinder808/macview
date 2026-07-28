import AppKit
import UniformTypeIdentifiers

/// Registers MacView as the default app for common image types via the modern
/// LaunchServices API (`NSWorkspace.setDefaultApplication`, macOS 12+). Sets the
/// default per concrete UTI — setting it for the abstract `public.image` doesn't
/// cascade to subtypes, since each (jpeg, png, …) carries its own association.
enum DefaultViewer {
    /// The concrete image types worth claiming. Each has its own per-type default.
    static let types: [UTType] = [
        .jpeg, .png, .gif, .tiff, .bmp, .heic, .heif, .webP, .rawImage,
    ]

    struct Outcome {
        var succeeded: Int
        var total: Int
        var lastError: Error?
    }

    /// Point the default app for each image type at this app bundle. Continues
    /// past per-type failures and reports how many stuck.
    static func makeDefault() async -> Outcome {
        let appURL = Bundle.main.bundleURL
        var succeeded = 0
        var lastError: Error?
        for type in types {
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
                succeeded += 1
            } catch {
                lastError = error
            }
        }
        return Outcome(succeeded: succeeded, total: types.count, lastError: lastError)
    }
}
