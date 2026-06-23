import Foundation
import UniformTypeIdentifiers

/// Builds the "folder as album" neighbor list: every image file sitting beside
/// the opened one, in Finder's natural (localized, numeric-aware) order.
enum FolderScanner {
    /// All image files in `folder`, natural-sorted by filename ascending.
    static func imageURLs(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentTypeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }
        return entries
            .filter { isImage($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// True if the URL is a regular file whose UTI conforms to `public.image`.
    static func isImage(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let type = values.contentType
        else { return false }
        return type.conforms(to: .image)
    }
}
