#if os(macOS)
  import AppKit

  extension NSImage {
    /// Renders `size`-point content into an image at an explicit backing `scale`.
    ///
    /// `NSImage.lockFocus` follows the host display's backing scale, so references recorded on a
    /// Retina Mac (@2x) do not match a headless CI runner (@1x). Passing a non-`nil` `scale` draws
    /// into a fixed-size `NSBitmapImageRep` instead, producing machine-portable references. When
    /// `scale` is `nil` the previous `lockFocus` behavior is preserved.
    static func snapshot(size: CGSize, scale: CGFloat?, draw: (CGContext) -> Void) -> NSImage {
      guard let scale = scale else {
        let image = NSImage(size: size)
        image.lockFocus()
        draw(NSGraphicsContext.current!.cgContext)
        image.unlockFocus()
        return image
      }

      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int((size.width * scale).rounded()),
        pixelsHigh: Int((size.height * scale).rounded()),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )!
      rep.size = size

      let context = NSGraphicsContext(bitmapImageRep: rep)!
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = context
      draw(context.cgContext)
      NSGraphicsContext.restoreGraphicsState()

      let image = NSImage(size: size)
      image.addRepresentation(rep)
      return image
    }
  }
#endif
