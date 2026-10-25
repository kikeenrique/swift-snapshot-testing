#if os(iOS) || os(tvOS) || os(macOS)
  import XCTest

  @testable import SnapshotTesting

  #if os(macOS)
    import Cocoa
  #else
    import UIKit
  #endif

  /// A reference and a newly-taken snapshot need not share a color space: on iOS a
  /// `UIGraphicsImageRenderer` render is extended sRGB, 16 bits per component, floating point,
  /// while its own PNG round trip decodes as Display P3, 16 bits per component, integer. The
  /// perceptual comparison runs with color management disabled, so unless both images are
  /// normalized first it reports a large delta E on every saturated pixel.
  ///
  /// These tests are fixture-free and record no snapshots: both images are synthesized in memory
  /// with identical content apart from a single altered pixel, so the expected result is exact.
  final class PerceptualColorSpaceTests: XCTestCase {
    private let width = 600
    private let height = 400
    private var totalPixelCount: Int { width * height }

    #if os(iOS) || os(tvOS)
      func testUIImageColorSpaceMismatchCountsOnlyTheAlteredPixel() throws {
        let (old, new) = try makeCrossColorSpacePair()
        let diffing = Diffing<UIImage>.image(precision: 1, perceptualPrecision: 0.98, scale: 1)
        let (message, _) = try XCTUnwrap(diffing.diffV2(old, new))
        XCTAssertEqual(
          try reportedPixelPrecision(in: message),
          1 - 1 / Float(totalPixelCount),
          accuracy: 1e-7
        )
      }

      func testUIImageColorSpaceMismatchIsNotAFailure() throws {
        let (old, new) = try makeCrossColorSpacePair()
        let diffing = Diffing<UIImage>.image(precision: 0.99, perceptualPrecision: 0.98, scale: 1)
        XCTAssertNil(diffing.diffV2(old, new))
      }

      private func makeCrossColorSpacePair() throws -> (UIImage, UIImage) {
        let (oldCgImage, newCgImage) = try makeCrossColorSpaceCGImagePair()
        return (
          UIImage(cgImage: oldCgImage, scale: 1, orientation: .up),
          UIImage(cgImage: newCgImage, scale: 1, orientation: .up)
        )
      }
    #endif

    #if os(macOS)
      func testNSImageColorSpaceMismatchCountsOnlyTheAlteredPixel() throws {
        let (old, new) = try makeCrossColorSpacePair()
        let diffing = Diffing<NSImage>.image(precision: 1, perceptualPrecision: 0.98)
        let (message, _) = try XCTUnwrap(diffing.diffV2(old, new))
        XCTAssertEqual(
          try reportedPixelPrecision(in: message),
          1 - 1 / Float(totalPixelCount),
          accuracy: 1e-7
        )
      }

      func testNSImageColorSpaceMismatchIsNotAFailure() throws {
        let (old, new) = try makeCrossColorSpacePair()
        let diffing = Diffing<NSImage>.image(precision: 0.99, perceptualPrecision: 0.98)
        XCTAssertNil(diffing.diffV2(old, new))
      }

      private func makeCrossColorSpacePair() throws -> (NSImage, NSImage) {
        let (oldCgImage, newCgImage) = try makeCrossColorSpaceCGImagePair()
        let size = NSSize(width: width, height: height)
        return (NSImage(cgImage: oldCgImage, size: size), NSImage(cgImage: newCgImage, size: size))
      }
    #endif

    // MARK: - Helpers

    /// "The percentage of pixels that match <value> is less than required <value>"
    private func reportedPixelPrecision(in message: String) throws -> Float {
      let line = try XCTUnwrap(message.split(separator: "\n").first)
      return try XCTUnwrap(Float(line.split(separator: " ")[6]))
    }

    /// The same content in two color spaces — sRGB at 8 bits per component, and Display P3 at 16,
    /// color-converted through a `CGContext` — differing in exactly one pixel.
    private func makeCrossColorSpaceCGImagePair() throws -> (CGImage, CGImage) {
      // The altered pixel sits inside the saturated block, where a color-space shift is largest.
      let alteredPixel = totalPixelCount / 2 + width / 2
      let old = try makeSaturatedImage(alteredPixel: nil)
      let new = try makeDisplayP3Copy(of: makeSaturatedImage(alteredPixel: alteredPixel))
      return (old, new)
    }

    /// A white field with a saturated olive block over its lower half: the shape of a screen whose
    /// only strongly-colored element is a button.
    private func makeSaturatedImage(alteredPixel: Int?) throws -> CGImage {
      var bytes = [UInt8](repeating: 255, count: totalPixelCount * 4)
      var index = totalPixelCount / 2
      while index < totalPixelCount {
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

    private func makeDisplayP3Copy(of cgImage: CGImage) throws -> CGImage {
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
  }
#endif
