import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Reads the handful of facts the info overlay shows — pixel size, file size,
/// type, and a few common EXIF fields — using ImageIO so no full decode is
/// needed. Runs off the main thread (callers await it from a Task).
enum MetadataReader {
    static func info(for url: URL) -> ImageInfo {
        var info = ImageInfo(name: url.lastPathComponent)

        // File size + type from the filesystem / UTI.
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey]) {
            info.fileSize = values.fileSize.map(Int64.init)
            info.typeDescription = values.contentType?.localizedDescription
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            // ImageIO can't read SVG; AppKit can, and reports its nominal size.
            if let size = NSImage(contentsOf: url)?.size, size.width > 0, size.height > 0 {
                info.pixelWidth = Int(size.width.rounded())
                info.pixelHeight = Int(size.height.rounded())
            }
            return info
        }

        info.pixelWidth = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        info.pixelHeight = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        // PixelWidth/Height are the *stored* dimensions. EXIF orientations 5–8
        // (portrait phone shots) display transposed — NSImage applies the
        // rotation — so swap to match what's actually on screen.
        if let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue,
           (5...8).contains(orientation) {
            swap(&info.pixelWidth, &info.pixelHeight)
        }

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            info.dateTaken = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            info.lens = exif[kCGImagePropertyExifLensModel] as? String
            info.exposure = exposureSummary(from: exif)
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            let make = tiff[kCGImagePropertyTIFFMake] as? String
            let model = tiff[kCGImagePropertyTIFFModel] as? String
            info.camera = [make, model].compactMap { $0 }.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
                .nilIfEmpty
        }
        return info
    }

    /// Compose "1/250s · f/2.8 · ISO 100" from whatever EXIF carries.
    private static func exposureSummary(from exif: [CFString: Any]) -> String? {
        var parts: [String] = []
        if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double, exposure > 0 {
            parts.append(exposure < 1 ? "1/\(Int((1 / exposure).rounded()))s" : "\(exposure)s")
        }
        if let fnum = exif[kCGImagePropertyExifFNumber] as? Double {
            parts.append("f/\(String(format: "%g", fnum))")
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first {
            parts.append("ISO \(iso.intValue)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
