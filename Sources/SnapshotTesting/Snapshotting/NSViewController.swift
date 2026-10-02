#if os(macOS)
  import AppKit
  import Cocoa

  extension Snapshotting where Value == NSViewController, Format == NSImage {
    /// A snapshot strategy for comparing view controller views based on pixel equality.
    public static var image: Snapshotting {
      return .image()
    }

    /// A snapshot strategy for comparing view controller views based on pixel equality.
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
    ///     references that are portable across machines. A view already hosted in a window is
    ///     temporarily re-hosted for the render and restored afterwards.
    public static func image(
      precision: Float = 1, perceptualPrecision: Float = 1, size: CGSize? = nil,
      appearance: NSAppearance? = nil, scale: CGFloat? = nil
    ) -> Snapshotting {
      return Snapshotting<NSView, NSImage>.image(
        precision: precision, perceptualPrecision: perceptualPrecision, size: size,
        appearance: appearance, scale: scale
      ).pullback { $0.view }
    }
  }

  extension Snapshotting where Value == NSViewController, Format == String {
    /// A snapshot strategy for comparing view controller views based on a recursive description of
    /// their properties and hierarchies.
    public static var recursiveDescription: Snapshotting {
      return Snapshotting<NSView, String>.recursiveDescription.pullback { $0.view }
    }
  }
#endif
