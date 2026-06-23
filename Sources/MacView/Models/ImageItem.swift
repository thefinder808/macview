import Foundation

/// A single image file in the current folder. Thin, identifiable wrapper around
/// its URL — pixel/EXIF detail is read on demand by `MetadataReader`.
struct ImageItem: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// On-demand metadata shown in the info overlay. All fields optional — readers
/// fill in whatever the file actually carries.
struct ImageInfo {
    var name: String
    var pixelWidth: Int?
    var pixelHeight: Int?
    var fileSize: Int64?
    var typeDescription: String?
    var dateTaken: String?
    var camera: String?
    var lens: String?
    var exposure: String?
}
