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

    /// Warm the cache for likely-next images (the neighbors of the current one).
    func prefetch(_ urls: [URL]) {
        for url in urls where cache[url] == nil {
            if let image = NSImage(contentsOf: url) {
                store(url, image)
            }
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
