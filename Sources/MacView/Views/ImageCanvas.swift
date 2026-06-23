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

final class ZoomableImageScrollView: NSScrollView {
    let imageView = NSImageView()

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
        maxMagnification = 40
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
        imageView.image = image
        imageView.animates = (image != nil)
        if let image {
            imageView.frame = NSRect(origin: .zero, size: pixelSize(of: image))
        } else {
            imageView.frame = .zero
        }
        fitImage()
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
        guard imageView.image != nil else { return }
        let center = NSPoint(x: imageView.frame.midX, y: imageView.frame.midY)
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

    /// Fit-to-window magnification, never exceeding 100% (small images show at
    /// actual size rather than being blown up).
    private func fitMagnification() -> CGFloat {
        guard let image = imageView.image else { return 1 }
        let ps = pixelSize(of: image)
        let viewport = bounds.size
        guard ps.width > 0, ps.height > 0, viewport.width > 0, viewport.height > 0 else { return 1 }
        let scale = min(viewport.width / ps.width, viewport.height / ps.height)
        return max(min(scale, 1.0), minMagnification)
    }

    private func clampMag(_ m: CGFloat) -> CGFloat { min(max(m, minMagnification), maxMagnification) }

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
        // Cmd-scroll always zooms (anchored at the cursor); plain scroll pans.
        if event.modifierFlags.contains(.command) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
            guard delta != 0 else { return }
            zoomBy(1 + delta * 0.01, centeredAt: imageView.convert(event.locationInWindow, from: nil))
        } else {
            super.scrollWheel(with: event)
        }
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
        switch event.clickCount {
        case 1:
            onClick?(zone(for: event))
        case 2:
            // The first click of a double already ran a center action (toggle
            // chrome); undo it for center clicks, then zoom. Edge double-clicks
            // just navigate once (from the first click) and then zoom.
            if zone(for: event) == .center { onClick?(.center) }
            toggleFitActual(at: imageView.convert(event.locationInWindow, from: nil))
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
