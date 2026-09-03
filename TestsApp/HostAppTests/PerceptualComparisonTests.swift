import CoreImage
import UIKit
import XCTest

@testable import SnapshotTesting

/// The perceptual comparator, exercised from inside a hosted application.
///
/// The package's own test bundle runs host-less and synthesises both images the same way, so it
/// cannot see a colour-space mismatch between a live render and a decoded PNG. This test builds
/// the pair the way a real snapshot does. It is fixture-free and records nothing.
final class PerceptualComparisonTests: XCTestCase {
  /// A live `UIGraphicsImageRenderer` render and its own PNG round trip are not in the same color
  /// space — the render is extended-sRGB 16-bit float, the decoded PNG is Display P3 16-bit
  /// integer — so a perceptual comparison of them as they arrive reads every saturated pixel as a
  /// large Delta E. Only the pixel that actually differs may be counted.
  func testLiveRenderAgainstItsPNGRoundTripCountsOnlyTheAlteredPixel() throws {
    let reference = try XCTUnwrap(UIImage(data: XCTUnwrap(renderSaturatedView().pngData())))
    let new = renderSaturatedView(alteringOnePixel: true)
    let old = try XCTUnwrap(reference.cgImage)
    let newCgImage = try XCTUnwrap(new.cgImage)
    let totalPixelCount = old.width * old.height

    let message = try XCTUnwrap(
      compareCore(
        old,
        newCgImage,
        oldSize: reference.size,
        newSize: new.size,
        precision: 1,
        perceptualPrecision: 0.98,
        pngRoundTrip: {
          guard let data = new.pngData() else { return nil }
          return UIImage(data: data)?.cgImage
        }
      )
    )
    let line = try XCTUnwrap(message.split(separator: "\n").first)
    let actual = try XCTUnwrap(Float(line.split(separator: " ")[6]))
    XCTAssertEqual(actual, 1 - 1 / Float(totalPixelCount), accuracy: 1e-7)
    XCTAssertEqual(Int((Float(totalPixelCount) * (1 - actual)).rounded()), 1)
  }

  /// White paper, a black bar, and one saturated olive rectangle: the shape of a real screen whose
  /// only strongly-coloured element is a button.
  private func renderSaturatedView(alteringOnePixel: Bool = false) -> UIImage {
    let traits = UITraitCollection(traitsFrom: [
      UITraitCollection(displayScale: 3),
      UITraitCollection(displayGamut: .P3),
    ])
    let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    let renderer = UIGraphicsImageRenderer(
      bounds: bounds, format: UIGraphicsImageRendererFormat(for: traits))
    return renderer.image { context in
      UIColor.white.setFill()
      context.fill(bounds)
      UIColor(red: 0.5, green: 0.55, blue: 0.1, alpha: 1).setFill()
      context.fill(CGRect(x: 40, y: 300, width: 100, height: 70))
      UIColor.black.setFill()
      context.fill(CGRect(x: 40, y: 100, width: 200, height: 12))
      if alteringOnePixel {
        UIColor.white.setFill()
        context.fill(CGRect(x: 60, y: 320, width: 1.0 / 3.0, height: 1.0 / 3.0))
      }
    }
  }
}
