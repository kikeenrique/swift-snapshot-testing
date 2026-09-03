#if os(iOS) || os(tvOS) || os(macOS)
  import Accelerate.vImage
  import CoreGraphics
  import CoreImage.CIKernel
  import Foundation
  import MetalPerformanceShaders

  // MARK: - Normalization

  // remap snapshot & reference to same colorspace
  let imageContextColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
  let imageContextBitsPerComponent = 8
  let imageContextBytesPerPixel = 4

  /// Draws `cgImage` into a freshly normalized sRGB / 8-bpc / 4-bpp / premultiplied-last context so
  /// that two images originating from different color spaces or bit depths compare byte-for-byte.
  func imageContext(for cgImage: CGImage, data: UnsafeMutableRawPointer? = nil) -> CGContext? {
    let bytesPerRow = cgImage.width * imageContextBytesPerPixel
    guard
      let colorSpace = imageContextColorSpace,
      let context = CGContext(
        data: data,
        width: cgImage.width,
        height: cgImage.height,
        bitsPerComponent: imageContextBitsPerComponent,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else { return nil }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    return context
  }

  let imageContextWideBitsPerComponent = 16
  let imageContextWideBytesPerPixel = 8

  /// Draws `cgImage` into a normalized sRGB / 16-bpc / 8-bpp / premultiplied-last context, so that
  /// two images of any bit depth or color space can be differenced in the same space at a precision
  /// finer than a single 8-bit code point.
  func wideImageContext(for cgImage: CGImage, data: UnsafeMutableRawPointer) -> CGContext? {
    guard
      let colorSpace = imageContextColorSpace,
      let context = CGContext(
        data: data,
        width: cgImage.width,
        height: cgImage.height,
        bitsPerComponent: imageContextWideBitsPerComponent,
        bytesPerRow: cgImage.width * imageContextWideBytesPerPixel,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          | CGBitmapInfo.byteOrder16Little.rawValue
      )
    else { return nil }

    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    return context
  }

  // MARK: - Compare

  /// The platform-neutral image comparison core shared by the `UIImage` and `NSImage` strategies.
  ///
  /// - Parameters:
  ///   - old: The reference image.
  ///   - new: The newly-taken snapshot.
  ///   - oldSize: The reference image's size in points, used only for the mismatch message.
  ///   - newSize: The new snapshot's size in points, used only for the mismatch message.
  ///   - precision: The percentage of pixels that must match.
  ///   - perceptualPrecision: The percentage a pixel must match the source pixel to be considered a
  ///     match.
  ///   - pngRoundTrip: Encodes `new` to PNG and decodes it back, so that the comparison tolerates
  ///     the lossy trip through the on-disk representation.
  /// - Returns: A failure message, or `nil` when the images match.
  func compareCore(
    _ old: CGImage,
    _ new: CGImage,
    oldSize: CGSize,
    newSize: CGSize,
    precision: Float,
    perceptualPrecision: Float,
    pngRoundTrip: () -> CGImage?
  ) -> String? {
    guard new.width != 0, new.height != 0 else {
      return "Newly-taken snapshot is empty."
    }
    guard old.width == new.width, old.height == new.height else {
      return "Newly-taken snapshot@\(newSize) does not match reference@\(oldSize)."
    }
    let pixelCount = old.width * old.height
    let byteCount = imageContextBytesPerPixel * pixelCount
    var oldBytes = [UInt8](repeating: 0, count: byteCount)
    guard let oldContext = imageContext(for: old, data: &oldBytes), let oldData = oldContext.data
    else {
      return "Reference image's data could not be loaded."
    }
    if let newContext = imageContext(for: new), let newData = newContext.data {
      if memcmp(oldData, newData, byteCount) == 0 { return nil }
    }
    var newerBytes = [UInt8](repeating: 0, count: byteCount)
    guard
      let newerCgImage = pngRoundTrip(),
      let newerContext = imageContext(for: newerCgImage, data: &newerBytes),
      let newerData = newerContext.data
    else {
      return "Newly-taken snapshot's data could not be loaded."
    }
    if memcmp(oldData, newerData, byteCount) == 0 { return nil }
    if precision >= 1, perceptualPrecision >= 1 {
      return "Newly-taken snapshot does not match reference."
    }
    if perceptualPrecision < 1, #available(iOS 11.0, tvOS 11.0, macOS 10.13, *) {
      // NB: `old` and `new` need not share a color space, a bit depth or an alpha layout. A
      //     reference decoded from PNG and a freshly rendered snapshot routinely do not: on iOS a
      //     `UIGraphicsImageRenderer` render is extended-sRGB 16-bit float, while its own PNG
      //     round trip decodes as Display P3 16-bit integer. The perceptual comparison runs with
      //     color management disabled, so it compares raw component values and must be handed
      //     images that are already in the same space, or every saturated pixel reads as a large
      //     Delta E. These are the very buffers the byte comparison above disagreed on.
      guard let oldNormalized = oldContext.makeImage(),
        let newNormalized = newerContext.makeImage()
      else {
        return "Newly-taken snapshot's data could not be processed."
      }
      return perceptuallyCompare(
        CIImage(cgImage: oldNormalized),
        CIImage(cgImage: newNormalized),
        pixelPrecision: precision,
        perceptualPrecision: perceptualPrecision
      )
    } else {
      let byteCountThreshold = Int((1 - precision) * Float(byteCount))
      var differentByteCount = 0
      // NB: We are purposely using a verbose 'while' loop instead of a 'for in' loop.  When the
      //     compiler doesn't have optimizations enabled, like in test targets, a `while` loop is
      //     significantly faster than a `for` loop for iterating through the elements of a memory
      //     buffer. Details can be found in [SR-6983](https://github.com/apple/swift/issues/49531)
      var index = 0
      while index < byteCount {
        defer { index += 1 }
        if oldBytes[index] != newerBytes[index] {
          differentByteCount += 1
        }
      }
      if differentByteCount > byteCountThreshold {
        let actualPrecision = 1 - Float(differentByteCount) / Float(byteCount)
        return "Actual image precision \(actualPrecision) is less than required \(precision)"
      }
    }
    return nil
  }

  // MARK: - Diff

  /// Produces a single-channel image whose brightness is the per-pixel maximum component difference
  /// between `old` and `new`, normalized against the largest difference in the image.
  ///
  /// Both images are redrawn into a shared 16-bits-per-component sRGB buffer, so they may be of any
  /// bit depth or color space, and a difference smaller than a single 8-bit code point still shows
  /// up in the output.
  func normalizedComponentDiff(_ old: CGImage, _ new: CGImage) -> CGImage? {
    guard old.width == new.width, old.height == new.height else {
      return nil
    }

    guard let outputColorSpace = CGColorSpace(name: CGColorSpace.linearGray),
      let outputFormat = vImage_CGImageFormat(
        bitsPerComponent: imageContextBitsPerComponent,
        bitsPerPixel: imageContextBitsPerComponent,
        colorSpace: outputColorSpace,
        bitmapInfo: .init()
      )
    else {
      return nil
    }

    let width = old.width
    let height = old.height
    let pixelCount = width * height
    guard pixelCount > 0 else { return nil }
    let componentCount = pixelCount * imageContextBytesPerPixel

    var oldComponents = [UInt16](repeating: 0, count: componentCount)
    var newComponents = [UInt16](repeating: 0, count: componentCount)
    guard wideImageContext(for: old, data: &oldComponents) != nil,
      wideImageContext(for: new, data: &newComponents) != nil
    else {
      return nil
    }

    var diffComponents = [UInt16](repeating: 0, count: pixelCount)
    var maximumDiff: UInt16 = 0

    // NB: We are purposely using a verbose 'while' loop instead of a 'for in' loop.  When the
    //     compiler doesn't have optimizations enabled, like in test targets, a `while` loop is
    //     significantly faster than a `for` loop for iterating through the elements of a memory
    //     buffer. Details can be found in [SR-6983](https://github.com/apple/swift/issues/49531)
    var index = 0
    while index < pixelCount {
      defer { index += 1 }
      let pixelOffset = index * imageContextBytesPerPixel

      var maxDiff: UInt16 = 0
      var component = 0
      while component < imageContextBytesPerPixel {
        defer { component += 1 }
        let oldComponent = oldComponents[pixelOffset + component]
        let newComponent = newComponents[pixelOffset + component]
        let diff =
          oldComponent > newComponent
          ? oldComponent - newComponent
          : newComponent - oldComponent
        if diff > maxDiff {
          maxDiff = diff
        }
      }

      diffComponents[index] = maxDiff
      if maxDiff > maximumDiff {
        maximumDiff = maxDiff
      }
    }

    guard maximumDiff > 0 else { return nil }

    // Normalize against the largest difference in the image so that a difference of a fraction of
    // an 8-bit code point is still visible in the attachment.
    var diffBytes = [UInt8](repeating: 0, count: pixelCount)
    index = 0
    while index < pixelCount {
      defer { index += 1 }
      diffBytes[index] = UInt8(Int(diffComponents[index]) * 255 / Int(maximumDiff))
    }

    return diffBytes.withUnsafeMutableBytes { diffPtr in
      var diffBuffer = vImage_Buffer(
        data: diffPtr.baseAddress,
        height: vImagePixelCount(height),
        width: vImagePixelCount(width),
        rowBytes: width
      )

      do {
        var normalizedBuffer = try vImage_Buffer(
          width: width,
          height: height,
          bitsPerPixel: UInt32(imageContextBitsPerComponent)
        )
        defer { normalizedBuffer.free() }

        let error = vImageContrastStretch_Planar8(
          &diffBuffer,
          &normalizedBuffer,
          vImage_Flags(kvImageNoFlags)
        )

        let buffer = error == kvImageNoError ? normalizedBuffer : diffBuffer

        return try buffer.createCGImage(format: outputFormat)
      } catch {
        return nil
      }
    }
  }

  // MARK: - Perceptual compare

  @available(iOS 10.0, tvOS 10.0, macOS 10.13, *)
  func perceptuallyCompare(
    _ old: CIImage, _ new: CIImage, pixelPrecision: Float, perceptualPrecision: Float
  ) -> String? {
    // Calculate the deltaE values. Each pixel is a value between 0-100.
    // 0 means no difference, 100 means completely opposite.
    let deltaOutputImage = old.applyingLabDeltaE(new)
    // Setting the working color space and output color space to NSNull disables color management. This is appropriate when the output
    // of the operations is computational instead of an image intended to be displayed.
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    let deltaThreshold = (1 - perceptualPrecision) * 100
    let actualPixelPrecision: Float
    var maximumDeltaE: Float = 0

    // Metal is supported by all iOS/tvOS devices (2013 models or later) and Macs (2012 models or later).
    // Older devices do not support iOS/tvOS 13 and macOS 10.15 which are the minimum versions of swift-snapshot-testing.
    // However, some virtualized hardware do not have GPUs and therefore do not support Metal.
    // In this case, macOS falls back to a CPU-based OpenGL ES renderer that silently fails when a Metal command is issued.
    // We need to check for Metal device support and fallback to CPU based vImage buffer iteration.
    if ThresholdImageProcessorKernel.isSupported {
      // Fast path - Metal processing
      guard
        let thresholdOutputImage = try? deltaOutputImage.applyingThreshold(deltaThreshold),
        let failingPixelCount = thresholdOutputImage.countingNonZeroPixels(in: context)
      else {
        return "Newly-taken snapshot's data could not be processed."
      }
      let failingPixelPercent =
        Float(failingPixelCount)
        / Float(deltaOutputImage.extent.width * deltaOutputImage.extent.height)
      actualPixelPrecision = 1 - failingPixelPercent
      if actualPixelPrecision < pixelPrecision {
        maximumDeltaE = deltaOutputImage.applyingAreaMaximum().renderSingleValue(in: context) ?? 0
      }
    } else {
      // Slow path - CPU based vImage buffer iteration
      guard let buffer = deltaOutputImage.render(in: context) else {
        return "Newly-taken snapshot could not be processed."
      }
      defer { buffer.free() }
      var failingPixelCount: Int = 0
      // rowBytes must be a multiple of 8, so vImage_Buffer pads the end of each row with bytes to meet the multiple of 0 requirement.
      // We must do 2D iteration of the vImage_Buffer in order to avoid loading the padding garbage bytes at the end of each row.
      //
      // NB: We are purposely using a verbose 'while' loop instead of a 'for in' loop.  When the
      //     compiler doesn't have optimizations enabled, like in test targets, a `while` loop is
      //     significantly faster than a `for` loop for iterating through the elements of a memory
      //     buffer. Details can be found in [SR-6983](https://github.com/apple/swift/issues/49531)
      let componentStride = MemoryLayout<Float>.stride
      var line = 0
      while line < buffer.height {
        defer { line += 1 }
        let lineOffset = buffer.rowBytes * line
        var column = 0
        while column < buffer.width {
          defer { column += 1 }
          let byteOffset = lineOffset + column * componentStride
          let deltaE = buffer.data.load(fromByteOffset: byteOffset, as: Float.self)
          if deltaE > deltaThreshold {
            failingPixelCount += 1
            if deltaE > maximumDeltaE {
              maximumDeltaE = deltaE
            }
          }
        }
      }
      let failingPixelPercent =
        Float(failingPixelCount)
        / Float(deltaOutputImage.extent.width * deltaOutputImage.extent.height)
      actualPixelPrecision = 1 - failingPixelPercent
    }

    guard actualPixelPrecision < pixelPrecision else { return nil }
    // The actual perceptual precision is the perceptual precision of the pixel with the highest DeltaE.
    // DeltaE is in a 0-100 scale, so we need to divide by 100 to transform it to a percentage.
    let minimumPerceptualPrecision = 1 - min(maximumDeltaE / 100, 1)
    return """
      The percentage of pixels that match \(actualPixelPrecision) is less than required \(pixelPrecision)
      The lowest perceptual color precision \(minimumPerceptualPrecision) is less than required \(perceptualPrecision)
      """
  }

  extension CIImage {
    func applyingLabDeltaE(_ other: CIImage) -> CIImage {
      applyingFilter("CILabDeltaE", parameters: ["inputImage2": other])
    }

    func applyingThreshold(_ threshold: Float) throws -> CIImage {
      try ThresholdImageProcessorKernel.apply(
        withExtent: extent,
        inputs: [self],
        arguments: [ThresholdImageProcessorKernel.inputThresholdKey: threshold]
      )
    }

    func applyingAreaMaximum() -> CIImage {
      // The extent is a `CIVector` parameter. Passing a `CGRect` only works where it happens to
      // bridge to an `NSValue` the filter can read, and raises `-[NSConcreteValue CGRectValue]:
      // unrecognized selector` elsewhere.
      applyingFilter("CIAreaMaximum", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
    }

    /// The number of pixels of a thresholded image that are not zero, i.e. the number of failing
    /// pixels.
    ///
    /// NB: This used to be derived from `CIAreaAverage`, whose single-value result is read back
    ///     through a 1x1 half-float render, quantizing the fraction to `Float16`: 1000 failing
    ///     pixels of 2,962,440 came back as 999.4. Counting the thresholded pixels keeps it
    ///     exact, and keeps the denominator ours rather than Core Image's.
    func countingNonZeroPixels(in context: CIContext) -> Int? {
      guard let buffer = render(in: context) else { return nil }
      defer { buffer.free() }
      var nonZeroPixelCount = 0
      // rowBytes must be a multiple of 8, so vImage_Buffer pads the end of each row with bytes to meet the multiple of 0 requirement.
      // We must do 2D iteration of the vImage_Buffer in order to avoid loading the padding garbage bytes at the end of each row.
      //
      // NB: We are purposely using a verbose 'while' loop instead of a 'for in' loop.  When the
      //     compiler doesn't have optimizations enabled, like in test targets, a `while` loop is
      //     significantly faster than a `for` loop for iterating through the elements of a memory
      //     buffer. Details can be found in [SR-6983](https://github.com/apple/swift/issues/49531)
      let componentStride = MemoryLayout<Float>.stride
      var line = 0
      while line < buffer.height {
        defer { line += 1 }
        let lineOffset = buffer.rowBytes * line
        var column = 0
        while column < buffer.width {
          defer { column += 1 }
          let byteOffset = lineOffset + column * componentStride
          if buffer.data.load(fromByteOffset: byteOffset, as: Float.self) > 0 {
            nonZeroPixelCount += 1
          }
        }
      }
      return nonZeroPixelCount
    }

    func renderSingleValue(in context: CIContext) -> Float? {
      guard let buffer = render(in: context) else { return nil }
      defer { buffer.free() }
      return buffer.data.load(fromByteOffset: 0, as: Float.self)
    }

    func render(in context: CIContext, format: CIFormat = CIFormat.Rh) -> vImage_Buffer? {
      // Some hardware configurations (virtualized CPU renderers) do not support 32-bit float output formats,
      // so use a compatible 16-bit float format and convert the output value to 32-bit floats.
      guard
        var buffer16 = try? vImage_Buffer(
          width: Int(extent.width), height: Int(extent.height), bitsPerPixel: 16)
      else { return nil }
      defer { buffer16.free() }
      context.render(
        self,
        toBitmap: buffer16.data,
        rowBytes: buffer16.rowBytes,
        bounds: extent,
        format: format,
        colorSpace: nil
      )
      guard
        var buffer32 = try? vImage_Buffer(
          width: Int(buffer16.width), height: Int(buffer16.height), bitsPerPixel: 32),
        vImageConvert_Planar16FtoPlanarF(&buffer16, &buffer32, 0) == kvImageNoError
      else { return nil }
      return buffer32
    }
  }

  // Copied from https://developer.apple.com/documentation/coreimage/ciimageprocessorkernel
  @available(iOS 10.0, tvOS 10.0, macOS 10.13, *)
  final class ThresholdImageProcessorKernel: CIImageProcessorKernel {
    static let inputThresholdKey = "thresholdValue"
    static let device = MTLCreateSystemDefaultDevice()

    static var isSupported: Bool {
      guard let device = device else {
        return false
      }
      #if targetEnvironment(simulator)
        guard #available(iOS 14.0, tvOS 14.0, *) else {
          // The MPSSupportsMTLDevice method throws an exception on iOS/tvOS simulators < 14.0
          return false
        }
      #endif
      return MPSSupportsMTLDevice(device)
    }

    override class func process(
      with inputs: [CIImageProcessorInput]?, arguments: [String: Any]?,
      output: CIImageProcessorOutput
    ) throws {
      guard
        let device = device,
        let commandBuffer = output.metalCommandBuffer,
        let input = inputs?.first,
        let sourceTexture = input.metalTexture,
        let destinationTexture = output.metalTexture,
        let thresholdValue = arguments?[inputThresholdKey] as? Float
      else {
        return
      }

      let threshold = MPSImageThresholdBinary(
        device: device,
        thresholdValue: thresholdValue,
        maximumValue: 1.0,
        linearGrayColorTransform: nil
      )

      threshold.encode(
        commandBuffer: commandBuffer,
        sourceTexture: sourceTexture,
        destinationTexture: destinationTexture
      )
    }
  }
#endif
