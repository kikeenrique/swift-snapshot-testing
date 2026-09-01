#if canImport(UIKit)
  import UIKit

  /// Aggregate statistics for a rectangular region of an image.
  ///
  /// These integration tests deliberately ship no reference images: instead of comparing against
  /// fixtures they assert on invariants of the captured pixels, which keeps them stable across
  /// system chrome redesigns.
  struct RegionStatistics {
    /// Average, un-premultiplied color components in `0...1`.
    var red: Double
    var green: Double
    var blue: Double
    /// Average alpha in `0...1`.
    var alpha: Double
    /// The fraction of sampled pixels whose alpha is at least `0.5`.
    var alphaCoverage: Double
    /// Average perceptual luminance in `0...1`.
    var luminance: Double
    /// Variance of the per-pixel luminance. A flat, single-color region is `~0`.
    var luminanceVariance: Double
    /// Number of pixels the statistics were computed over.
    var pixelCount: Int

    /// The largest per-channel distance between two regions' average colors, in `0...1`.
    func colorDistance(to other: RegionStatistics) -> Double {
      max(
        abs(red - other.red),
        max(abs(green - other.green), max(abs(blue - other.blue), abs(alpha - other.alpha)))
      )
    }
  }

  extension UIImage {
    /// Samples a region of the image, expressed in unit coordinates with the origin at the top
    /// left, and returns aggregate statistics for it.
    ///
    /// - Parameter unitRect: The region to sample, in `0...1` coordinates.
    /// - Returns: Statistics for the region, or `nil` if the image has no pixels there.
    func statistics(in unitRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1))
      -> RegionStatistics?
    {
      guard let pixels = self.pixels(in: unitRect) else { return nil }

      let count = pixels.count
      guard count > 0 else { return nil }

      var totalRed = 0.0
      var totalGreen = 0.0
      var totalBlue = 0.0
      var totalAlpha = 0.0
      var opaqueCount = 0
      var luminances = [Double]()
      luminances.reserveCapacity(count)

      for pixel in pixels {
        totalRed += pixel.red
        totalGreen += pixel.green
        totalBlue += pixel.blue
        totalAlpha += pixel.alpha
        if pixel.alpha >= 0.5 { opaqueCount += 1 }
        luminances.append(pixel.luminance)
      }

      let mean = luminances.reduce(0, +) / Double(count)
      let variance =
        luminances.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(count)

      return RegionStatistics(
        red: totalRed / Double(count),
        green: totalGreen / Double(count),
        blue: totalBlue / Double(count),
        alpha: totalAlpha / Double(count),
        alphaCoverage: Double(opaqueCount) / Double(count),
        luminance: mean,
        luminanceVariance: variance,
        pixelCount: count
      )
    }

    /// The fraction of pixels in a region that differ from the corresponding pixel of another
    /// image by more than `tolerance` on any channel.
    ///
    /// Both images must have the same pixel dimensions.
    func fractionOfPixelsDiffering(
      from other: UIImage,
      in unitRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
      tolerance: Double = 0.05
    ) -> Double? {
      guard
        let lhs = self.pixels(in: unitRect),
        let rhs = other.pixels(in: unitRect),
        lhs.count == rhs.count,
        !lhs.isEmpty
      else { return nil }

      var differing = 0
      for index in lhs.indices where lhs[index].distance(to: rhs[index]) > tolerance {
        differing += 1
      }
      return Double(differing) / Double(lhs.count)
    }

    private func pixels(in unitRect: CGRect) -> [Pixel]? {
      guard let cgImage = self.cgImage else { return nil }

      let imageWidth = CGFloat(cgImage.width)
      let imageHeight = CGFloat(cgImage.height)
      let cropRect =
        CGRect(
          x: unitRect.minX * imageWidth,
          y: unitRect.minY * imageHeight,
          width: unitRect.width * imageWidth,
          height: unitRect.height * imageHeight
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

      guard
        cropRect.width >= 1, cropRect.height >= 1,
        let cropped = cgImage.cropping(to: cropRect)
      else { return nil }

      let width = cropped.width
      let height = cropped.height
      let bytesPerPixel = 4
      let bytesPerRow = width * bytesPerPixel
      var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)

      guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = bytes.withUnsafeMutableBytes({ buffer in
          CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
        })
      else { return nil }

      context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

      var pixels = [Pixel]()
      pixels.reserveCapacity(width * height)
      var offset = 0
      while offset < bytes.count {
        defer { offset += bytesPerPixel }
        let alpha = Double(bytes[offset + 3]) / 255
        // The context is premultiplied, so recover the source color before averaging.
        let divisor = alpha == 0 ? 1 : alpha * 255
        pixels.append(
          Pixel(
            red: alpha == 0 ? 0 : Double(bytes[offset]) / divisor,
            green: alpha == 0 ? 0 : Double(bytes[offset + 1]) / divisor,
            blue: alpha == 0 ? 0 : Double(bytes[offset + 2]) / divisor,
            alpha: alpha
          )
        )
      }
      return pixels
    }
  }

  private struct Pixel {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var luminance: Double {
      (0.2126 * red + 0.7152 * green + 0.0722 * blue) * alpha
    }

    func distance(to other: Pixel) -> Double {
      max(
        abs(red - other.red),
        max(abs(green - other.green), max(abs(blue - other.blue), abs(alpha - other.alpha)))
      )
    }
  }
#endif
