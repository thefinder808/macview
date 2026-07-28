import Foundation

/// On-demand metadata shown in the info overlay, read by `MetadataReader`. All
/// fields optional — readers fill in whatever the file actually carries.
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
