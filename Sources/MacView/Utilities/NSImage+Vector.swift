import AppKit

extension NSImage {
    /// True for resolution-independent images (SVG). Vector reps carry no pixel
    /// grid, so they report `NSImageRepMatchesDevice` (0) for their pixel size.
    var isVector: Bool {
        guard let rep = representations.first else { return false }
        return rep.pixelsWide <= 0 || rep.pixelsHigh <= 0
    }

    /// Caps a vector's nominal size so its longest side is at most `maxSide`
    /// points. An SVG can declare any size it likes (`width="1e40"`), and
    /// `NSImageView` allocates a bitmap that big to draw it — AppKit throws and
    /// the app dies. A vector loses nothing by being drawn at a smaller nominal
    /// size; only what "100%" means changes. Bitmaps are left alone.
    func clampVectorSize(maxSide: CGFloat = 4096) {
        guard isVector else { return }
        let w = size.width, h = size.height
        guard w.isFinite, h.isFinite, w > 0, h > 0 else {
            size = NSSize(width: maxSide, height: maxSide)
            return
        }
        let longest = max(w, h)
        guard longest > maxSide else { return }
        let scale = maxSide / longest
        size = NSSize(width: max(1, (w * scale).rounded()),
                      height: max(1, (h * scale).rounded()))
    }

    /// Draws the image into a bitmap whose longest side is `maxPixel`, keeping
    /// the aspect ratio. Vectors scale up to fill it; bitmaps never upscale.
    /// This is the path for formats AppKit can draw but ImageIO can't decode.
    func rasterized(maxPixel: CGFloat) -> CGImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        var scale = maxPixel / max(size.width, size.height)
        if !isVector { scale = min(scale, 1) }
        let w = max(1, Int((size.width * scale).rounded()))
        let h = max(1, Int((size.height * scale).rounded()))

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: w,
                  height: h,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
