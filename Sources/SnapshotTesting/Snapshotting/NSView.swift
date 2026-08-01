#if os(macOS)
  import AppKit
  import Cocoa

  extension Snapshotting where Value == NSView, Format == NSImage {
    /// A snapshot strategy for comparing views based on pixel equality.
    public static var image: Snapshotting {
      return .image()
    }

    /// A snapshot strategy for comparing views based on pixel equality.
    ///
    /// > Note: Snapshots must be compared on the same OS as the device that originally took the
    /// > reference to avoid discrepancies between images.
    ///
    /// - Parameters:
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered a
    ///     match. 98-99% mimics
    ///     [the precision](http://zschuessler.github.io/DeltaE/learn/#toc-defining-delta-e) of the
    ///     human eye.
    ///   - size: A view size override.
    ///   - appearance: An appearance override (e.g. `NSAppearance(named: .darkAqua)`); `nil` uses
    ///     the inherited appearance.
    ///   - scale: A rendering scale override (e.g. `2` for @2x). `nil` follows the host display's
    ///     backing scale, which makes references machine-dependent; pin a scale to record
    ///     references that are portable across machines. A pinned scale is fully honored for
    ///     views not yet attached to a window (they are temporarily hosted in an offscreen window
    ///     that rasterizes at that scale); for a view already in a window the pinned scale sizes
    ///     the bitmap and the drawing transform, but layer-backed content (e.g. text) keeps
    ///     rasterizing at that window's backing scale. Does not apply to SceneKit, SpriteKit, or
    ///     WebKit views, which render through their own snapshot APIs at a fixed @2x.
    public static func image(
      precision: Float = 1, perceptualPrecision: Float = 1, size: CGSize? = nil,
      appearance: NSAppearance? = nil, scale: CGFloat? = nil
    ) -> Snapshotting {
      return SimplySnapshotting.image(
        precision: precision, perceptualPrecision: perceptualPrecision
      ).asyncPullback { view in
        let initialSize = view.frame.size
        if let size = size { view.frame.size = size }
        if let appearance = appearance { view.appearance = appearance }
        guard view.frame.width > 0, view.frame.height > 0 else {
          fatalError("View not renderable to image at size \(view.frame.size)")
        }
        return view.snapshot
          ?? Async { callback in
            addImagesForRenderedViews(view).sequence().run { views in
              let bitmapRep: NSBitmapImageRep
              if let scale = scale {
                let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int(view.bounds.width * scale),
                  pixelsHigh: Int(view.bounds.height * scale),
                  bitsPerSample: 8,
                  samplesPerPixel: 4,
                  hasAlpha: true,
                  isPlanar: false,
                  colorSpaceName: .calibratedRGB,
                  bytesPerRow: 0,
                  bitsPerPixel: 0
                )!
                rep.size = view.bounds.size
                bitmapRep = rep
                // `cacheDisplay(in:to:)` rasterizes at the view's backing scale, and a windowless
                // view falls back to 1x — stretching a soft 1x render into the 2x rep. Hosting the
                // view in an offscreen window that reports the pinned scale makes AppKit rasterize
                // at that scale.
                if view.window == nil {
                  let window = ScaledWindow(scale: scale, contentRect: view.bounds)
                  window.contentView = view
                  view.layoutSubtreeIfNeeded()
                  view.cacheDisplay(in: view.bounds, to: rep)
                  window.contentView = nil
                  // Detaching dirties layout flags across the subtree, which would leak into a
                  // subsequent `recursiveDescription` snapshot — settle them back down.
                  view.layoutSubtreeIfNeeded()
                } else {
                  view.cacheDisplay(in: view.bounds, to: rep)
                }
              } else {
                bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmapRep)
              }
              let image = NSImage(size: view.bounds.size)
              image.addRepresentation(bitmapRep)
              callback(image)
              views.forEach { $0.removeFromSuperview() }
              view.frame.size = initialSize
            }
          }
      }
    }
  }

  /// An offscreen window that reports a fixed backing scale, so `cacheDisplay(in:to:)` rasterizes
  /// hosted views at that scale instead of the host display's.
  private final class ScaledWindow: NSWindow {
    private let scale: CGFloat

    init(scale: CGFloat, contentRect: NSRect) {
      self.scale = scale
      super.init(
        contentRect: contentRect, styleMask: [.borderless], backing: .buffered, defer: false)
      self.isReleasedWhenClosed = false
    }

    override var backingScaleFactor: CGFloat { self.scale }
  }

  extension Snapshotting where Value == NSView, Format == String {
    /// A snapshot strategy for comparing views based on a recursive description of their properties
    /// and hierarchies.
    ///
    /// ``` swift
    /// assertSnapshot(of: view, as: .recursiveDescription)
    /// ```
    ///
    /// Records:
    ///
    /// ```
    /// [   AF      LU ] h=--- v=--- NSButton "Push Me" f=(0,0,77,32) b=(-)
    ///   [   A       LU ] h=--- v=--- NSButtonBezelView f=(0,0,77,32) b=(-)
    ///   [   AF      LU ] h=--- v=--- NSButtonTextField "Push Me" f=(10,6,57,16) b=(-)
    /// ```
    public static var recursiveDescription: Snapshotting<NSView, String> {
      return SimplySnapshotting.lines.pullback { view in
        return purgePointers(
          view.perform(Selector(("_subtreeDescription"))).retain().takeUnretainedValue()
            as! String
        )
      }
    }
  }
#endif
