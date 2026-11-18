import AppKit
import Combine
import UniformTypeIdentifiers

/// The single source of truth for the viewing session: which folder of images
/// we're paging through, where we are in it, the decoded image on screen, and
/// the transient view state (rotation, chrome/overlay visibility, zoom readout).
///
/// Not annotated `@MainActor`: all mutation happens on the main thread already
/// (SwiftUI body, menu actions, and AppKit canvas callbacks all run there);
/// the only off-main work is image decoding inside the `ImageLoader` actor, and
/// those results are published back via `MainActor.run`.
final class ViewerModel: ObservableObject {
    // Folder-as-album state.
    @Published private(set) var urls: [URL] = []
    @Published private(set) var index: Int = 0

    // The image actually shown (base rotated by `rotation`).
    @Published private(set) var displayImage: NSImage?
    @Published private(set) var rotation: Int = 0   // clockwise degrees, multiple of 90
    /// Why the current file shows nothing, once its load has finished empty.
    @Published private(set) var loadProblem: String?

    // Chrome / overlays.
    @Published var chromeVisible = true
    @Published var filmstripVisible = true
    @Published var infoVisible = false

    // Info overlay payload + delete confirmation.
    @Published var info: ImageInfo?
    @Published var showDeleteConfirm = false

    private var baseImage: NSImage?
    private let loader = ImageLoader()
    let thumbnailer = Thumbnailer()
    private var loadToken = 0

    // MARK: Derived

    var current: URL? { urls.indices.contains(index) ? urls[index] : nil }
    var count: Int { urls.count }
    var hasNext: Bool { index < urls.count - 1 }
    var hasPrevious: Bool { index > 0 }
    var currentName: String? { current?.lastPathComponent }
    var isEmpty: Bool { urls.isEmpty }

    // MARK: Opening

    /// Open `url` and build the neighbor list from its folder so Next/Previous
    /// works immediately. Falls back to a single-item list if the folder can't
    /// be enumerated (e.g. a permission edge case).
    func open(url: URL) {
        let folder = url.deletingLastPathComponent()
        let list = FolderScanner.imageURLs(in: folder)
        if let i = list.firstIndex(of: url) {
            urls = list
            index = i
        } else {
            urls = [url]
            index = 0
        }
        loadCurrent()
    }

    /// Show the system Open panel filtered to images, and open the choice.
    func openWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            open(url: url)
        }
    }

    // MARK: Navigation

    func next() {
        guard hasNext else { return }
        index += 1
        loadCurrent()
    }

    func previous() {
        guard hasPrevious else { return }
        index -= 1
        loadCurrent()
    }

    func jump(to target: Int) {
        guard urls.indices.contains(target), target != index else { return }
        index = target
        loadCurrent()
    }

    // MARK: Rotation (non-destructive — view only, never rewrites the file)

    func rotateLeft() { rotation = normalize(rotation - 90); updateDisplayImage() }
    func rotateRight() { rotation = normalize(rotation + 90); updateDisplayImage() }

    // MARK: File actions

    /// Copy the current image (as shown, including rotation) plus its file URL to
    /// the pasteboard, so it can be pasted as an image or as a file.
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        var items: [NSPasteboardWriting] = []
        if let image = displayImage { items.append(image) }
        if let url = current { items.append(url as NSURL) }
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }

    /// Reveal the current file in Finder.
    func revealInFinder() {
        guard let url = current else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Delete

    /// Either trash immediately or raise the confirmation, per the preference.
    func requestDelete() {
        guard current != nil else { return }
        if SettingsManager.shared.confirmBeforeDelete {
            showDeleteConfirm = true
        } else {
            performDelete()
        }
    }

    /// Move the current file to Trash, drop it from the list, and auto-advance.
    func performDelete() {
        guard let url = current else { return }
        do {
            try FileActions.trash(url)
        } catch {
            NSSound.beep()
            presentError(error)
            return
        }
        urls.remove(at: index)
        if urls.isEmpty {
            index = 0
            setBase(nil)
            info = nil
            return
        }
        if index >= urls.count { index = urls.count - 1 }
        loadCurrent()
    }

    // MARK: Chrome toggles

    func toggleChrome() { chromeVisible.toggle() }

    /// Policy for a click on the image canvas. While the chrome is hidden, any
    /// click just reveals it (the chevrons aren't shown to aim at). While it's
    /// visible, an edge click navigates (matching the on-screen chevron there)
    /// and a center click hides the chrome again.
    func handleClick(_ zone: ClickZone) {
        guard chromeVisible else {
            chromeVisible = true   // any click while hidden just reveals the chrome
            return
        }
        switch zone {
        case .left:
            if hasPrevious { previous() } else { chromeVisible = false }
        case .right:
            if hasNext { next() } else { chromeVisible = false }
        case .center:
            chromeVisible = false
        }
    }
    func toggleFilmstrip() { filmstripVisible.toggle() }
    func toggleInfo() {
        infoVisible.toggle()
        if infoVisible, info == nil { loadInfo() }
    }

    // MARK: Loading internals

    private func loadCurrent() {
        rotation = 0
        info = nil
        loadProblem = nil
        guard let url = current else { setBase(nil); return }

        loadToken += 1
        let token = loadToken
        Task {
            let image = await loader.load(url)
            await MainActor.run {
                guard token == self.loadToken else { return }   // a newer navigation won
                self.setBase(image)
                if image == nil {
                    self.loadProblem = VectorProbe.wasRefused(url)
                        ? "This image needs too much memory to display."
                        : "This image can’t be displayed."
                }
            }
            // Prefetch neighbors one actor call at a time, re-checking between
            // decodes that navigation hasn't moved on — a stale batch shouldn't
            // keep burning decodes ahead of the image the user is now waiting on.
            let neighbors = await MainActor.run { self.neighborURLs() }
            for neighbor in neighbors {
                guard await MainActor.run(body: { token == self.loadToken }) else { break }
                await loader.prefetch(neighbor)
            }
        }
        if infoVisible { loadInfo() }
    }

    private func loadInfo() {
        guard let url = current else { return }
        let token = loadToken
        Task {
            let read = MetadataReader.info(for: url)
            await MainActor.run {
                guard token == self.loadToken else { return }
                self.info = read
            }
        }
    }

    private func setBase(_ image: NSImage?) {
        baseImage = image
        updateDisplayImage()
    }

    private func updateDisplayImage() {
        guard let base = baseImage else { displayImage = nil; return }
        displayImage = rotation == 0 ? base : base.rotatedClockwise(rotation)
    }

    /// The ±2 neighbors to warm in the cache for instant paging.
    private func neighborURLs() -> [URL] {
        var result: [URL] = []
        for offset in [-2, -1, 1, 2] {
            let i = index + offset
            if urls.indices.contains(i) { result.append(urls[i]) }
        }
        return result
    }

    private func normalize(_ degrees: Int) -> Int { ((degrees % 360) + 360) % 360 }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}
