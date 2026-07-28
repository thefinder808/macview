import AppKit

/// Decodes full-resolution images off the main thread and keeps a small
/// most-recently-used cache so paging Next/Previous through neighbors is
/// instant. An `actor` so the cache is touched serially without locks; its
/// methods run off the main actor, so `NSImage(contentsOf:)` decoding never
/// blocks the UI.
actor ImageLoader {
    private var cache: [URL: NSImage] = [:]
    private var order: [URL] = []        // LRU, most-recent last
    private let capacity = 7             // current ± a couple of neighbors

    /// Returns the decoded image for `url`, caching it. Returns nil if the file
    /// can't be decoded.
    func load(_ url: URL) -> NSImage? {
        if let cached = cache[url] {
            touch(url)
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        store(url, image)
        return image
    }

    /// Warm the cache for one likely-next image. One URL per call on purpose:
    /// each decode is its own actor turn, so a `load` from a fresh keypress
    /// interleaves between neighbor decodes instead of queueing behind a whole
    /// batch (which made held-arrow paging hitch on large images).
    func prefetch(_ url: URL) {
        guard cache[url] == nil else { return }
        if let image = NSImage(contentsOf: url) {
            store(url, image)
        }
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
