#if os(iOS) || os(tvOS) || os(visionOS)
  import UIKit

  extension Diffing where Value == UIImage {
    /// A pixel-diffing strategy for UIImage's which requires a 100% match.
    public static let image = Diffing.image()

    /// A pixel-diffing strategy for UIImage that allows customizing how precise the matching must be.
    ///
    /// - Parameters:
    ///   - precision: The percentage of pixels that must match.
    ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered a
    ///     match. 98-99% mimics
    ///     [the precision](http://zschuessler.github.io/DeltaE/learn/#toc-defining-delta-e) of the
    ///     human eye.
    ///   - scale: Scale to use when loading the reference image from disk. If `nil` or the
    ///     `UITraitCollection`s default value of `0.0`, the screens scale is used.
    /// - Returns: A new diffing strategy.
    public static func image(
      precision: Float = 1, perceptualPrecision: Float = 1, scale: CGFloat? = nil
    ) -> Diffing {
      let imageScale: CGFloat
      if let scale = scale, scale != 0.0 {
        imageScale = scale
      } else {
        #if os(visionOS)
          // visionOS has no UIScreen, so there is no screen scale to fall back on. Content
          // rasterizes at a default @2x scale factor unless a layer opts in to dynamic content
          // scaling, which doesn't apply to offscreen rendering. See "Drawing sharp layer-based
          // content in visionOS":
          // https://developer.apple.com/documentation/visionos/drawing-sharp-layer-based-content
          //
          // NB: This is only the scale the reference is *decoded* at. The reference is re-tagged
          //     with the newly-taken snapshot's scale below, so failure messages report point
          //     sizes in the snapshot's own scale rather than always assuming @2x.
          imageScale = 2.0
        #else
          imageScale = UIScreen.main.scale
        #endif
      }
      let toData: (UIImage) -> Data = { $0.pngData() ?? emptyImage().pngData()! }
      return .diff(
        toData: toData,
        fromData: { UIImage(data: $0, scale: imageScale)! }
      ) { old, new in
        #if os(visionOS)
          // Without a screen scale, the reference was decoded at a fixed default scale. Re-tag it
          // with the newly-taken snapshot's scale so both images describe their (identical) pixel
          // buffers in the same point space. An explicitly requested scale always wins.
          let old = scale == nil || scale == 0.0 ? rescaled(old, to: new.scale) : old
        #endif
        guard
          let message = compare(
            old, new, precision: precision, perceptualPrecision: perceptualPrecision)
        else { return nil }
        let difference = SnapshotTesting.diff(old, new)
        let isEmptyImage = new.size == .zero
        let referenceAttachment = DiffAttachment.data(toData(old), name: "reference.png")
        let failureAttachment = DiffAttachment.data(
          toData(isEmptyImage ? emptyImage() : new),
          name: "failure.png"
        )
        let differenceAttachment = DiffAttachment.data(toData(difference), name: "difference.png")
        return (
          message,
          [referenceAttachment, failureAttachment, differenceAttachment]
        )
      }
    }

    #if os(visionOS)
      /// Re-tags an image with a different scale, leaving its pixel buffer untouched. Used to
      /// describe a reference image in the same point space as the newly-taken snapshot.
      private static func rescaled(_ image: UIImage, to scale: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage, scale > 0, scale != image.scale else { return image }
        return UIImage(cgImage: cgImage, scale: scale, orientation: image.imageOrientation)
      }
    #endif

    /// Used when the image size has no width or no height to generated the default empty image
    private static func emptyImage() -> UIImage {
      let label = UILabel(frame: CGRect(x: 0, y: 0, width: 400, height: 80))
      label.backgroundColor = .red
      label.text =
        "Error: No image could be generated for this view as its size was zero. Please set an explicit size in the test."
      label.textAlignment = .center
      label.numberOfLines = 3
      return label.asImage()
    }
  }

  extension Snapshotting where Value == UIImage, Format == UIImage {
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
    ///   - scale: The scale of the reference image stored on disk.
    public static func image(
      precision: Float = 1, perceptualPrecision: Float = 1, scale: CGFloat? = nil
    ) -> Snapshotting {
      return .init(
        pathExtension: "png",
        diffing: .image(
          precision: precision, perceptualPrecision: perceptualPrecision, scale: scale)
      )
    }
  }

  private func compare(_ old: UIImage, _ new: UIImage, precision: Float, perceptualPrecision: Float)
    -> String?
  {
    guard let oldCgImage = old.cgImage else {
      return "Reference image could not be loaded."
    }
    guard let newCgImage = new.cgImage else {
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
      guard let pngData = new.pngData() else { return nil }
      return UIImage(data: pngData)?.cgImage
    }
  }

  private func diff(_ old: UIImage, _ new: UIImage) -> UIImage {
    normalizedComponentDiff(old, new)
      ?? blendModeDiff(old, new)
  }

  private func blendModeDiff(_ old: UIImage, _ new: UIImage) -> UIImage {
    let width = max(old.size.width, new.size.width)
    let height = max(old.size.height, new.size.height)
    let scale = max(old.scale, new.scale)
    UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), true, scale)
    new.draw(at: .zero)
    old.draw(at: .zero, blendMode: .difference, alpha: 1)
    let differenceImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return differenceImage
  }

  private func normalizedComponentDiff(_ old: UIImage, _ new: UIImage) -> UIImage? {
    guard let oldCgImage = old.cgImage,
      let pngData = new.pngData(),
      let newCgImage = UIImage(data: pngData)?.cgImage,
      let outputCgImage = SnapshotTesting.normalizedComponentDiff(oldCgImage, newCgImage)
    else {
      return nil
    }

    return UIImage(cgImage: outputCgImage, scale: old.scale, orientation: .up)
  }
#endif
