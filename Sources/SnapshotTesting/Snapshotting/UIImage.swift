#if os(iOS) || os(tvOS)
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
        imageScale = UIScreen.main.scale
      }
      let toData: (UIImage) -> Data = { $0.pngData() ?? emptyImage().pngData()! }
      return .diff(
        toData: toData,
        fromData: { UIImage(data: $0, scale: imageScale)! }
      ) { old, new in
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
