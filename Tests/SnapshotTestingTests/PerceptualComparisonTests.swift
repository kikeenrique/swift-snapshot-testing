#if os(iOS) || os(tvOS) || os(macOS)
  import CoreImage
  import XCTest

  @testable import SnapshotTesting

  /// Fixture-free unit tests for the perceptual image comparator.
  ///
  /// These record no snapshots: every image is synthesised in memory with a known number of
  /// differing pixels, so the tests can assert the exact failing-pixel fraction the comparator
  /// reports, on the host and in the simulator alike.
  @available(iOS 11.0, tvOS 11.0, macOS 10.13, *)
  final class PerceptualComparisonTests: XCTestCase {
    /// The comparator must report `1 - failingPixels / totalPixels`, exactly, no matter how the
    /// differing pixels are distributed across the image.
    func testActualPixelPrecisionMatchesTheExactFailingPixelCount() throws {
      for size in [(width: 1170, height: 2532), (width: 2752, height: 2064)] {
        for differingPixelCount in [10, 83, 137, 1000] {
          for clustered in [false, true] {
            let (old, new) = try makeImagePair(
              width: size.width,
              height: size.height,
              differingPixelCount: differingPixelCount,
              clustered: clustered
            )
            let message = try XCTUnwrap(
              perceptuallyCompare(
                CIImage(cgImage: old),
                CIImage(cgImage: new),
                pixelPrecision: 1,
                perceptualPrecision: 0.98
              ),
              "Expected a failure message for \(differingPixelCount) differing pixels"
            )
            let totalPixelCount = size.width * size.height
            let actual = try actualPixelPrecision(in: message)
            let expected = 1 - Float(differingPixelCount) / Float(totalPixelCount)
            XCTAssertEqual(
              actual,
              expected,
              accuracy: 1e-7,
              """
              \(size.width)x\(size.height), \(differingPixelCount) differing pixels, \
              clustered: \(clustered)
              """
            )
            XCTAssertEqual(
              Int((Float(totalPixelCount) * (1 - actual)).rounded()),
              differingPixelCount,
              """
              \(size.width)x\(size.height), \(differingPixelCount) differing pixels, \
              clustered: \(clustered)
              """
            )
          }
        }
      }
    }

    /// `CIAreaMaximum` takes its extent as a `CIVector`. Passing a `CGRect` only works where it
    /// happens to bridge to an `NSValue` the filter can read, and raises
    /// `-[NSConcreteValue CGRectValue]: unrecognized selector` elsewhere.
    func testAreaMaximumAcceptsTheImageExtent() throws {
      let (old, new) = try makeImagePair(
        width: 64, height: 64, differingPixelCount: 8, clustered: false)
      let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
      let delta = CIImage(cgImage: old).applyingLabDeltaE(CIImage(cgImage: new))
      let maximum = try XCTUnwrap(delta.applyingAreaMaximum().renderSingleValue(in: context))
      XCTAssertGreaterThan(maximum, 0)
    }

    /// A reference and a snapshot need not share a color space: on iOS a `UIGraphicsImageRenderer`
    /// render is extended-sRGB 16-bit float while its own PNG round trip decodes as Display P3
    /// 16-bit integer. The perceptual comparison runs with color management disabled, so comparing
    /// them as they arrive reads every saturated pixel as a large Delta E. `compareCore` must
    /// compare the normalized buffers instead, and report only the pixels that actually differ.
    func testColorSpaceMismatchDoesNotCountAsFailingPixels() throws {
      let width = 600
      let height = 400
      let totalPixelCount = width * height
      // The altered pixel sits inside the saturated block, where a color-space shift is largest.
      let alteredPixel = totalPixelCount / 2 + width / 2
      let old = try makeSaturatedImage(width: width, height: height, alteredPixel: nil)
      let altered = try makeSaturatedImage(
        width: width, height: height, alteredPixel: alteredPixel)
      let new = try makeWideDisplayP3Copy(of: altered)

      let message = try XCTUnwrap(
        compareCore(
          old,
          new,
          oldSize: CGSize(width: width, height: height),
          newSize: CGSize(width: width, height: height),
          precision: 1,
          perceptualPrecision: 0.98,
          pngRoundTrip: { new }
        )
      )
      let actual = try actualPixelPrecision(in: message)
      XCTAssertEqual(actual, 1 - 1 / Float(totalPixelCount), accuracy: 1e-7)
      XCTAssertEqual(Int((Float(totalPixelCount) * (1 - actual)).rounded()), 1)
    }

    /// A 16-bit-per-component pair whose difference is smaller than one 8-bit code point must still
    /// produce a visible difference image, at the pixels that actually differ.
    func testDifferenceOfSixteenBitImagesIsNotBlank() throws {
      let width = 32
      let height = 32
      // Put the differing pixels in the bottom half of the image: a difference computed with an
      // 8-bit stride over a 16-bit buffer only ever reaches the top half.
      let differingIndices = [width * height - 1, width * height - 17]
      let (old, new) = try makeSixteenBitImagePair(
        width: width, height: height, differingIndices: differingIndices)
      let difference = try XCTUnwrap(normalizedComponentDiff(old, new))
      let differenceBytes = try grayBytes(of: difference)
      XCTAssertEqual(differenceBytes.count, width * height)
      for index in differingIndices {
        XCTAssertGreaterThan(
          differenceBytes[index], 0, "Difference is blank at differing pixel \(index)")
      }
      XCTAssertEqual(
        differenceBytes.enumerated().filter { $0.element > 0 }.map(\.offset).sorted(),
        differingIndices.sorted()
      )
    }

    // MARK: - Helpers

    private func actualPixelPrecision(in message: String) throws -> Float {
      // "The percentage of pixels that match <value> is less than required <value>"
      let line = try XCTUnwrap(message.split(separator: "\n").first)
      let fields = line.split(separator: " ")
      return try XCTUnwrap(Float(fields[6]))
    }

    private func makeImagePair(
      width: Int, height: Int, differingPixelCount: Int, clustered: Bool
    ) throws -> (CGImage, CGImage) {
      let pixelCount = width * height
      var oldBytes = [UInt8](repeating: 255, count: pixelCount * 4)
      var index = 0
      while index < pixelCount {
        defer { index += 1 }
        oldBytes[index * 4] = 128
        oldBytes[index * 4 + 1] = 128
        oldBytes[index * 4 + 2] = 128
      }
      var newBytes = oldBytes
      let stride = clustered ? 1 : max(1, pixelCount / max(differingPixelCount, 1))
      var differing = 0
      while differing < differingPixelCount {
        defer { differing += 1 }
        let pixel = differing * stride
        newBytes[pixel * 4] = 255
        newBytes[pixel * 4 + 1] = 255
        newBytes[pixel * 4 + 2] = 255
      }
      return (
        try makeCGImage(oldBytes, width: width, height: height),
        try makeCGImage(newBytes, width: width, height: height)
      )
    }

    private func makeCGImage(_ bytes: [UInt8], width: Int, height: Int) throws -> CGImage {
      let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
      return try XCTUnwrap(
        CGImage(
          width: width,
          height: height,
          bitsPerComponent: 8,
          bitsPerPixel: 32,
          bytesPerRow: width * 4,
          space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
          provider: provider,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent
        )
      )
    }

    /// A white field with a saturated olive block over its lower half, optionally with one pixel
    /// turned black. sRGB, 8 bits per component.
    private func makeSaturatedImage(
      width: Int, height: Int, alteredPixel: Int?
    ) throws -> CGImage {
      let pixelCount = width * height
      var bytes = [UInt8](repeating: 255, count: pixelCount * 4)
      var index = pixelCount / 2
      while index < pixelCount {
        defer { index += 1 }
        bytes[index * 4] = 128
        bytes[index * 4 + 1] = 140
        bytes[index * 4 + 2] = 25
      }
      if let alteredPixel {
        bytes[alteredPixel * 4] = 0
        bytes[alteredPixel * 4 + 1] = 0
        bytes[alteredPixel * 4 + 2] = 0
      }
      return try makeCGImage(bytes, width: width, height: height)
    }

    /// The same content, properly color-converted into Display P3 at 16 bits per component.
    private func makeWideDisplayP3Copy(of cgImage: CGImage) throws -> CGImage {
      let width = cgImage.width
      let height = cgImage.height
      let context = try XCTUnwrap(
        CGContext(
          data: nil,
          width: width,
          height: height,
          bitsPerComponent: 16,
          bytesPerRow: width * 8,
          space: XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder16Little.rawValue
        )
      )
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return try XCTUnwrap(context.makeImage())
    }

    private func makeSixteenBitImagePair(
      width: Int, height: Int, differingIndices: [Int]
    ) throws -> (CGImage, CGImage) {
      let pixelCount = width * height
      var oldComponents = [UInt16](repeating: .max, count: pixelCount * 4)
      var index = 0
      while index < pixelCount {
        defer { index += 1 }
        oldComponents[index * 4] = 32768
        oldComponents[index * 4 + 1] = 32768
        oldComponents[index * 4 + 2] = 32768
      }
      var newComponents = oldComponents
      for pixel in differingIndices {
        // 96/65535 is well below one 8-bit code point (257/65535).
        newComponents[pixel * 4] = 32768 + 96
        newComponents[pixel * 4 + 1] = 32768 + 96
        newComponents[pixel * 4 + 2] = 32768 + 96
      }
      return (
        try makeSixteenBitCGImage(oldComponents, width: width, height: height),
        try makeSixteenBitCGImage(newComponents, width: width, height: height)
      )
    }

    private func makeSixteenBitCGImage(
      _ components: [UInt16], width: Int, height: Int
    ) throws -> CGImage {
      let data = components.withUnsafeBufferPointer { Data(buffer: $0) }
      let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
      return try XCTUnwrap(
        CGImage(
          width: width,
          height: height,
          bitsPerComponent: 16,
          bitsPerPixel: 64,
          bytesPerRow: width * 8,
          space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
          bitmapInfo: CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
              | CGBitmapInfo.byteOrder16Little.rawValue
          ),
          provider: provider,
          decode: nil,
          shouldInterpolate: false,
          intent: .defaultIntent
        )
      )
    }

    private func grayBytes(of cgImage: CGImage) throws -> [UInt8] {
      let width = cgImage.width
      let height = cgImage.height
      var bytes = [UInt8](repeating: 0, count: width * height)
      let context = try XCTUnwrap(
        CGContext(
          data: &bytes,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width,
          space: XCTUnwrap(CGColorSpace(name: CGColorSpace.linearGray)),
          bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
      )
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
      return bytes
    }
  }
#endif
