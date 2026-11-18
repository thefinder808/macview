import SwiftUI
import AppKit

/// Which horizontal third of the canvas a click landed in. The canvas reliably
/// receives image clicks (bare SwiftUI overlays lose hit-testing to an embedded
/// NSView), so edge-click navigation is handled here deterministically rather
/// than via tappable chevron buttons that the canvas would swallow anyway.
enum ClickZone { case left, center, right }

/// Lets SwiftUI chrome (toolbar buttons, menu items) drive the AppKit canvas's
/// zoom without owning it. The canvas registers itself here on creation.
final class CanvasController: ObservableObject {
    /// Live zoom readout for the toolbar. Lives here (ContentView scope), NOT on
    /// the App-scoped ViewerModel: it changes on every pinch/scroll tick, and an
    /// App-scoped publisher would rebuild the `commands` menu on each tick —
    /// which cancels menu tracking and makes items vanish.
    @Published var zoomPercent: Int = 100

    fileprivate weak var view: ZoomableImageScrollView?

    func fit() { view?.fitImage() }
    func actualSize() { view?.zoomToActualSize() }
    func zoomIn() { view?.zoomBy(1.25) }
    func zoomOut() { view?.zoomBy(1 / 1.25) }
}

/// The image surface. AppKit (NSScrollView magnification) owns zoom/pan because
/// it handles large images and gesture math far more efficiently than SwiftUI;
/// SwiftUI just hands it the current image and receives callbacks.
struct ImageCanvas: NSViewRepresentable {
    @ObservedObject var model: ViewerModel
    let controller: CanvasController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ZoomableImageScrollView {
        let view = ZoomableImageScrollView()
        controller.view = view
        view.onZoomChange = { [weak controller] pct in controller?.zoomPercent = pct }
        view.onClick = { [weak model] zone in model?.handleClick(zone) }
        view.onPrevious = { [weak model] in model?.previous() }
        view.onNext = { [weak model] in model?.next() }
        view.onToggleChrome = { [weak model] in model?.toggleChrome() }
        view.onDelete = { [weak model] in model?.requestDelete() }
        return view
    }

    func updateNSView(_ view: ZoomableImageScrollView, context: Context) {
        controller.view = view
        // Swap the image only when it actually changed (identity), so unrelated
        // state updates (chrome toggles, zoom readouts) don't reset zoom/pan.
        if context.coordinator.shownImage !== model.displayImage {
            context.coordinator.shownImage = model.displayImage
            view.setImage(model.displayImage)
        }
    }

    final class Coordinator {
        var shownImage: NSImage?
    }
}

/// Centers the document view in the viewport when it's smaller than the viewport
/// (NSClipView otherwise pins to the bottom-left), and clamps panning when it's
/// larger. This is what makes a small image sit centered on the dark backdrop.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        let docFrame = doc.frame
        if rect.width > docFrame.width {
            rect.origin.x = (docFrame.width - rect.width) / 2
        }
        if rect.height > docFrame.height {
            rect.origin.y = (docFrame.height - rect.height) / 2
        }
        return rect
    }
}

/// Document view for vector images (SVG, and the rotated copies of one). `NSImageView` rasterizes the *whole* image at the zoomed size, so its
/// memory grows with the square of the zoom. A plain `draw(_:)` view doesn't:
/// under a magnified `NSScrollView`, AppKit backs only the visible rect, so the
/// cost is one viewport of pixels whatever the zoom. The rep is drawn directly —
/// `NSImage.draw` goes through the image's bitmap cache and comes out blurry.
/// Deliberately unflipped and mouse-transparent, like the `NSImageView` it
/// stands in for, so clicks and drags still reach the scroll view.
final class VectorImageView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        image?.representations.first?.draw(in: bounds)
    }

    // Same accessibility role `NSImageView` gives a bitmap.
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
}

final class ZoomableImageScrollView: NSScrollView {
    /// Document view for bitmaps (and what plays animated GIFs).
    let imageView = NSImageView()
    /// Document view for vectors; `setImage` swaps between the two.
    let vectorView = VectorImageView()
    private var image: NSImage?

    // Callbacks into the view model (all fire on the main thread).
    var onZoomChange: ((Int) -> Void)?
    var onClick: ((ClickZone) -> Void)?
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onToggleChrome: (() -> Void)?
    var onDelete: (() -> Void)?

    /// True while the image is showing at its fit magnification, so a window
    /// resize re-fits instead of leaving it stuck at a stale zoom.
    private var isFitted = false
    private var lastDragPoint: NSPoint?
    private var didDrag = false
    private var keyMonitor: Any?
    private var swipeAccumX: CGFloat = 0
    private var swipeNavigated = false
    private var lastScrollTime = Date.distantPast

    init() {
        super.init(frame: .zero)

        let clip = CenteringClipView()
        clip.drawsBackground = false
        contentView = clip

        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.animates = true
        documentView = imageView

        hasVerticalScroller = false
        hasHorizontalScroller = false
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = 0.05
        maxMagnification = Self.zoomCeiling
        drawsBackground = false

        postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(frameChanged),
                           name: NSView.frameDidChangeNotification, object: self)
        center.addObserver(self, selector: #selector(liveMagnifyEnded),
                           name: NSScrollView.didEndLiveMagnifyNotification, object: self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    // Handle navigation keys via a local event monitor rather than relying on
    // first-responder status: SwiftUI's hosting view keeps first responder, so a
    // plain keyDown override on this AppKit view never fires. The monitor sees
    // key-downs while our window is key (and no sheet is up), routes the ones we
    // care about, and passes the rest through.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  let window = self.window,
                  window.isKeyWindow,
                  window.attachedSheet == nil
            else { return event }
            switch event.keyCode {
            case 123: self.onPrevious?(); return nil       // ←
            case 124: self.onNext?(); return nil           // →
            case 49:  self.onToggleChrome?(); return nil   // space
            case 51, 117: self.onDelete?(); return nil     // delete / fn-delete
            case 53:                                        // esc → leave fullscreen
                if window.styleMask.contains(.fullScreen) {
                    window.toggleFullScreen(nil); return nil
                }
                return event
            default:
                return event
            }
        }
    }

    // MARK: Image

    func setImage(_ image: NSImage?) {
        self.image = image
        let isVector = image?.isVector == true
        imageView.image = isVector ? nil : image
        imageView.animates = (imageView.image != nil)
        vectorView.image = isVector ? image : nil
        let doc: NSView = isVector ? vectorView : imageView
        if documentView !== doc { documentView = doc }
        maxMagnification = image.map(zoomCeiling(for:)) ?? Self.zoomCeiling
        doc.frame = NSRect(origin: .zero, size: image.map(pixelSize(of:)) ?? .zero)
        fitImage()
    }

    /// The most any image may be magnified (4000%).
    private static let zoomCeiling: CGFloat = 40
    /// Largest bitmap (in pixels) a zoomed vector may be rendered into, on
    /// systems where `VectorImageView`'s memory hasn't been measured.
    private static let vectorPixelBudget: CGFloat = 32_000_000

    /// Upper zoom bound for `image`: the plain ceiling for bitmaps, and for
    /// vectors on macOS 27+, where `VectorImageView` was measured to cost one
    /// viewport of pixels at any zoom (a 4096pt SVG at 4000% peaks ~345 MB).
    ///
    /// Older systems keep the pixel budget, because that visible-rect backing is
    /// AppKit's doing and unverified there. If the whole image were rasterized
    /// instead — as `NSImageView` does — the bitmap would grow with the square
    /// of the zoom: a 4096pt SVG at 1500% asked for ~230 GB. The budget keeps it
    /// bounded. Drop the availability check, and the budget with it, once an
    /// older macOS has been measured (see CLAUDE.md).
    private func zoomCeiling(for image: NSImage) -> CGFloat {
        guard image.isVector else { return Self.zoomCeiling }
        if #available(macOS 27, *) { return Self.zoomCeiling }
        let ps = pixelSize(of: image)
        // The densest attached screen, so moving the window can't exceed it.
        let backing = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let area = ps.width * ps.height * backing * backing
        guard area > 0, area.isFinite else { return Self.zoomCeiling }
        let cap = (Self.vectorPixelBudget / area).squareRoot()
        return min(Self.zoomCeiling, max(minMagnification, cap))
    }

    /// Best pixel dimensions for the image (so 100% means one image pixel per
    /// point and "fit" math is exact), falling back to the point size.
    private func pixelSize(of image: NSImage) -> NSSize {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }

    // MARK: Zoom

    func fitImage() {
        guard image != nil, let doc = documentView else { return }
        let center = NSPoint(x: doc.frame.midX, y: doc.frame.midY)
        setMagnification(fitMagnification(), centeredAt: center)
        isFitted = true
        report()
    }

    func zoomToActualSize() {
        setMagnification(clampMag(1.0), centeredAt: visibleCenterInDoc())
        isFitted = false
        report()
    }

    func zoomBy(_ factor: CGFloat) { zoomBy(factor, centeredAt: visibleCenterInDoc()) }

    func zoomBy(_ factor: CGFloat, centeredAt point: NSPoint) {
        setMagnification(clampMag(magnification * factor), centeredAt: point)
        isFitted = false
        report()
    }

    /// Double-click toggles between fit and 100%, anchored on the click point.
    func toggleFitActual(at point: NSPoint) {
        if abs(magnification - fitMagnification()) < 0.01 {
            setMagnification(clampMag(1.0), centeredAt: point)
            isFitted = false
        } else {
            fitImage()
        }
        report()
    }

    /// Fit-to-window magnification. Bitmaps never exceed 100% (small images show
    /// at actual size rather than being blown up); vectors (SVG) have no pixel
    /// grid to blur, so a small icon scales up to fill the window.
    private func fitMagnification() -> CGFloat {
        guard let image else { return 1 }
        let ps = pixelSize(of: image)
        let viewport = bounds.size
        guard ps.width > 0, ps.height > 0, viewport.width > 0, viewport.height > 0 else { return 1 }
        let scale = min(viewport.width / ps.width, viewport.height / ps.height)
        let cap = image.isVector ? maxMagnification : 1.0
        return max(min(scale, cap), minMagnification)
    }

    private func clampMag(_ m: CGFloat) -> CGFloat { min(max(m, minMagnification), maxMagnification) }

    /// The event's location in the current document view (bitmap or vector).
    private func documentPoint(for event: NSEvent) -> NSPoint {
        documentView?.convert(event.locationInWindow, from: nil) ?? .zero
    }

    private func visibleCenterInDoc() -> NSPoint {
        let r = contentView.documentVisibleRect
        return NSPoint(x: r.midX, y: r.midY)
    }

    private func report() { onZoomChange?(Int((magnification * 100).rounded())) }

    @objc private func frameChanged() { if isFitted { fitImage() } }
    @objc private func liveMagnifyEnded() { isFitted = false; report() }

    // MARK: Gestures

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)   // AppKit applies the pinch
        isFitted = false
        report()
    }

    override func scrollWheel(with event: NSEvent) {
        // Cmd-scroll always zooms (anchored at the cursor).
        if event.modifierFlags.contains(.command) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
            guard delta != 0 else { return }
            zoomBy(1 + delta * 0.01, centeredAt: documentPoint(for: event))
            return
        }

        // Two-finger horizontal swipe pages between images — but only when the
        // image can't be panned horizontally (otherwise horizontal scroll pans).
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        let displayedWidth = (documentView?.frame.width ?? 0) * magnification
        let canPanHorizontally = displayedWidth > bounds.width + 1
        if !canPanHorizontally, abs(dx) > abs(dy), abs(dx) > 0.1 {
            // Ignore the momentum tail that glides after a trackpad swipe lifts
            // off — accumulating it would page through several images for a
            // second or two after the finger leaves the pad.
            if event.momentumPhase != [] { return }

            let now = Date()
            let hasPhase = event.phase != []
            // Start a fresh gesture when a trackpad swipe begins, or — for
            // phase-less line scrolls (mouse wheel) — after a pause.
            if event.phase.contains(.began) || (!hasPhase && now.timeIntervalSince(lastScrollTime) > 0.18) {
                swipeAccumX = 0
                swipeNavigated = false
            }
            lastScrollTime = now
            swipeAccumX += dx

            // At most one page-turn per swipe. Direction matches the macOS Spaces
            // gesture — a left swipe moves "rightward" to the next image.
            if !swipeNavigated, abs(swipeAccumX) >= 50 {
                swipeNavigated = true
                if swipeAccumX > 0 { onPrevious?() } else { onNext?() }
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                swipeAccumX = 0
                swipeNavigated = false
            }
            return
        }

        super.scrollWheel(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        didDrag = false
        lastDragPoint = event.locationInWindow
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last = lastDragPoint else { lastDragPoint = event.locationInWindow; return }
        didDrag = true
        let now = event.locationInWindow
        let dx = now.x - last.x
        let dy = now.y - last.y
        lastDragPoint = now

        // Grab-and-drag: content follows the cursor (origin moves opposite),
        // scaled into document coordinates. Constrained so it can't pan to void.
        let mag = magnification
        var origin = contentView.bounds.origin
        origin.x -= dx / mag
        origin.y -= dy / mag
        let constrained = contentView.constrainBoundsRect(
            NSRect(origin: origin, size: contentView.bounds.size)
        ).origin
        contentView.setBoundsOrigin(constrained)
        reflectScrolledClipView(contentView)
    }

    override func mouseUp(with event: NSEvent) {
        defer { lastDragPoint = nil }
        if didDrag { return }

        let z = zone(for: event)
        if z != .center {
            // Edge: every click navigates, including rapid clicks (which macOS
            // reports as double-clicks). Never zoom here — that's what made a
            // fast second arrow-click jump to 100% instead of advancing.
            onClick?(z)
            return
        }

        // Center: single click toggles chrome; double click toggles fit ⇄ 100%.
        switch event.clickCount {
        case 1:
            onClick?(.center)
        case 2:
            onClick?(.center)   // undo the chrome toggle the first click ran
            toggleFitActual(at: documentPoint(for: event))
        default:
            break
        }
    }

    /// The horizontal third the click landed in, with a generous edge band so the
    /// visual chevrons have a forgiving hit target.
    private func zone(for event: NSEvent) -> ClickZone {
        let x = convert(event.locationInWindow, from: nil).x
        let band: CGFloat = 96
        if x < band { return .left }
        if x > bounds.width - band { return .right }
        return .center
    }
}
