#if os(macOS)
  import Cocoa
  import XCTest

  extension Diffing where Value == NSImage {
    /// A pixel-diffing strategy for NSImage's which requires a 100% match.
    public static let image = Diffing.image()

    /// A pixel-diffing strategy for NSImage that allows customizing how precise the matching must be.
    ///
    /// - Parameters:
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered a
    ///     match. 98-99% mimics
    ///     [the precision](http://zschuessler.github.io/DeltaE/learn/#toc-defining-delta-e) of the
    ///     human eye.
    /// - Returns: A new diffing strategy.
    public static func image(precision: Float = 1, perceptualPrecision: Float = 1) -> Diffing {
      return .diff(
        toData: { NSImagePNGRepresentation($0)! },
        fromData: { NSImage(data: $0)! }
      ) { old, new in
        guard
          let message = compare(
            old, new, precision: precision, perceptualPrecision: perceptualPrecision)
        else { return nil }
        let difference = SnapshotTesting.diff(old, new)
        let oldAttachment = DiffAttachment.data(
          NSImagePNGRepresentation(old)!, name: "reference.png")
        let newAttachment = DiffAttachment.data(NSImagePNGRepresentation(new)!, name: "failure.png")
        let differenceAttachment = DiffAttachment.data(
          NSImagePNGRepresentation(difference)!, name: "difference.png")
        return (
          message,
          [oldAttachment, newAttachment, differenceAttachment]
        )
      }
    }
  }

  extension Snapshotting where Value == NSImage, Format == NSImage {
    /// A snapshot strategy for comparing images based on pixel equality.
    public static var image: Snapshotting {
      return .image()
    }

    /// A snapshot strategy for comparing images based on pixel equality.
    ///
    /// - Parameters:
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered a
    ///     match. 98-99% mimics
    ///     [the precision](http://zschuessler.github.io/DeltaE/learn/#toc-defining-delta-e) of the
    ///     human eye.
    public static func image(precision: Float = 1, perceptualPrecision: Float = 1) -> Snapshotting {
      return .init(
        pathExtension: "png",
        diffing: .image(precision: precision, perceptualPrecision: perceptualPrecision)
      )
    }
  }

  private func NSImagePNGRepresentation(_ image: NSImage) -> Data? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = image.size
    return rep.representation(using: .png, properties: [:])
  }

  private func compare(_ old: NSImage, _ new: NSImage, precision: Float, perceptualPrecision: Float)
    -> String?
  {
    guard let oldCgImage = old.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return "Reference image could not be loaded."
    }
    guard let newCgImage = new.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return "Newly-taken snapshot could not be loaded."
    }
    return compareCore(
      oldCgImage,
      newCgImage,
      oldSize: old.size,
      newSize: new.size,
      precision: precision,
      perceptualPrecision: perceptualPrecision
    ) {
      guard let pngData = NSImagePNGRepresentation(new) else { return nil }
      return NSImage(data: pngData)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
  }

  private func diff(_ old: NSImage, _ new: NSImage) -> NSImage {
    normalizedComponentDiff(old, new)
      ?? blendModeDiff(old, new)
  }

  private func normalizedComponentDiff(_ old: NSImage, _ new: NSImage) -> NSImage? {
    guard let oldCgImage = old.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let pngData = NSImagePNGRepresentation(new),
      let newCgImage = NSImage(data: pngData)?.cgImage(
        forProposedRect: nil, context: nil, hints: nil),
      let outputCgImage = SnapshotTesting.normalizedComponentDiff(oldCgImage, newCgImage)
    else {
      return nil
    }

    let rep = NSBitmapImageRep(cgImage: outputCgImage)
    rep.size = old.size
    let difference = NSImage(size: old.size)
    difference.addRepresentation(rep)
    return difference
  }

  private func blendModeDiff(_ old: NSImage, _ new: NSImage) -> NSImage {
    let oldCiImage = CIImage(cgImage: old.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    let newCiImage = CIImage(cgImage: new.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    let differenceFilter = CIFilter(name: "CIDifferenceBlendMode")!
    differenceFilter.setValue(oldCiImage, forKey: kCIInputImageKey)
    differenceFilter.setValue(newCiImage, forKey: kCIInputBackgroundImageKey)
    let maxSize = CGSize(
      width: max(old.size.width, new.size.width),
      height: max(old.size.height, new.size.height)
    )
    let rep = NSCIImageRep(ciImage: differenceFilter.outputImage!)
    let difference = NSImage(size: maxSize)
    difference.addRepresentation(rep)
    return difference
  }
#endif
