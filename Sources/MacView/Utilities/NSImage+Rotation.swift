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

    /// Rotation for vector images (SVG): a custom rep that replays the source
    /// rep through a rotated transform, so the copy is still a vector — sharp at
    /// any zoom, same nominal size, and no more memory than the original. This
    /// relies on the canvas drawing the rep itself (`VectorImageView`); anything
    /// that goes through `NSImage`'s cache (`NSImageView`, `NSImage.draw`) gets a
    /// bitmap at the nominal size instead.
    private func vectorRotatedClockwise(_ n: Int) -> NSImage {
        guard let source = representations.first else { return self }
        let src = size
        let swap = (n == 90 || n == 270)
        let newSize = swap ? NSSize(width: src.height, height: src.width) : src
        let rep = NSCustomImageRep(size: newSize, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.translateBy(x: rect.midX, y: rect.midY)
            // CGContext positive rotation is counter-clockwise; negate for clockwise.
            ctx.rotate(by: -CGFloat(n) * .pi / 180)
            source.draw(in: NSRect(x: -src.width / 2, y: -src.height / 2,
                                   width: src.width, height: src.height))
            ctx.restoreGState()
            return true
        }
        let rotated = NSImage(size: newSize)
        rotated.addRepresentation(rep)
        return rotated
    }
}
