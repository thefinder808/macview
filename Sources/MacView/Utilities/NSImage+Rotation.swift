import AppKit

extension NSImage {
    /// Returns a pixel-preserving copy rotated **clockwise** by `clockwise`
    /// degrees (must be a multiple of 90). Rendered through a CGContext at the
    /// source's pixel dimensions so rotation never downsamples the image. Used
    /// for MacView's non-destructive on-screen rotation — the file is untouched.
    func rotatedClockwise(_ clockwise: Int) -> NSImage {
        let n = ((clockwise % 360) + 360) % 360
        if n == 0 { return self }
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
}
