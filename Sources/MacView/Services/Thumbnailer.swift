import AppKit
import ImageIO

/// Produces small, cached thumbnails for the bottom filmstrip via ImageIO,
/// which decodes only enough of each file to fill the requested pixel size —
/// far cheaper than loading every full image. An `actor` for lock-free caching.
actor Thumbnailer {
    private var cache: [URL: NSImage] = [:]
    private let maxPixel: CGFloat = 200   // generous for Retina filmstrip rows

    func thumbnail(for url: URL) -> NSImage? {
        if let cached = cache[url] { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respect EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache[url] = image
        return image
    }
}
