import AppKit

/// Filesystem mutations the viewer performs. Kept tiny and explicit so the one
/// destructive action (delete) is easy to audit.
enum FileActions {
    /// Move a file to the macOS Trash (recoverable — never a hard delete).
    static func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
