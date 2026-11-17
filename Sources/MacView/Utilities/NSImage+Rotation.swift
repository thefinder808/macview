import AppKit

extension NSImage {
    /// Returns a pixel-preserving copy rotated **clockwise** by `clockwise`
    /// degrees (must be a multiple of 90). Rendered through a CGContext at the
    /// source's pixel dimensions so rotation never downsamples the image. Used
    /// for MacView's non-destructive on-screen rotation — the file is untouched.
    func rotatedClockwise(_ clockwise: Int) -> NSImage {
        let n = ((clockwise % 360) + 360) % 360
        if n == 0 { return self }
        if isVector { return vectorRotatedClockwise(n) }
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }

        let w = cg.width
        let h = cg.height
        let swap = (n == 90 || n == 270)
        let newW = swap ? h : w
        let newH = swap ? w : h

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil,
                  width: newW,
                  height: newH,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return self }

        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(newW) / 2, y: CGFloat(newH) / 2)
        // CGContext positive rotation is counter-clockwise; negate for clockwise.
        ctx.rotate(by: -CGFloat(n) * .pi / 180)
        ctx.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let out = ctx.makeImage() else { return self }
        return NSImage(cgImage: out, size: NSSize(width: newW, height: newH))
    }

    /// Rotation for vector images (SVG): replays the source through a rotated
    /// transform into an in-memory PDF, so the copy is still a vector — sharp at
    /// any zoom, same nominal size. Rasterizing would bake in the screen scale,
    /// and a drawing-handler `NSImage` gets cached at its nominal size (a 24pt
    /// icon turned to mush when zoomed).
    private func vectorRotatedClockwise(_ n: Int) -> NSImage {
        let src = size
        let swap = (n == 90 || n == 270)
        let newSize = swap ? NSSize(width: src.height, height: src.width) : src
        var box = CGRect(origin: .zero, size: newSize)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return self }

        ctx.beginPDFPage(nil)
        ctx.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        ctx.rotate(by: -CGFloat(n) * .pi / 180)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        draw(in: NSRect(x: -src.width / 2, y: -src.height / 2,
                        width: src.width, height: src.height))
        NSGraphicsContext.restoreGraphicsState()
        ctx.endPDFPage()
        ctx.closePDF()
        return NSImage(data: data as Data) ?? self
    }
}
