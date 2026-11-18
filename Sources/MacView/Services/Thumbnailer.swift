import AppKit
import ImageIO

/// Produces small, cached thumbnails for the bottom filmstrip via ImageIO,
/// which decodes only enough of each file to fill the requested pixel size —
/// far cheaper than loading every full image. Formats ImageIO can't decode
/// (SVG) are drawn through AppKit in a child process (`VectorProbe`). An
/// `actor` for lock-free caching.
actor Thumbnailer {
    private var cache: [URL: NSImage] = [:]
    private var order: [URL] = []         // LRU, most-recent last
    private let capacity = 256            // ≈40 MB worst case at 200px — bounded
                                          // so a huge folder can't grow memory forever
    private let maxPixel: CGFloat = 200   // generous for Retina filmstrip rows

    func thumbnail(for url: URL) -> NSImage? {
        if let cached = cache[url] {
            touch(url)
            return cached
        }
        // ImageIO has no SVG decoder, so fall back to AppKit (which does). That
        // draw happens in a child process: an SVG can make it cost gigabytes even
        // at thumbnail size, and this runs for files the user never opened.
        guard let cg = imageIOThumbnail(for: url)
                ?? VectorProbe.thumbnail(for: url, maxPixel: maxPixel)
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        store(url, image)
        return image
    }

    private func imageIOThumbnail(for url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // respect EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func store(_ url: URL, _ image: NSImage) {
        cache[url] = image
        touch(url)
        while order.count > capacity {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }
}
