#if os(iOS) || os(tvOS)
  @testable import SnapshotTesting
  import XCTest

  // This test bundle runs host-less, so no key window exists: exactly the environment in which
  // `drawHierarchyInKeyWindow` used to hit a `fatalError` that took down every test in the
  // bundle. These tests assert it now fails only the offending test and falls back to a
  // host-less window rendered with `layer.render`.
  final class DrawHierarchyInKeyWindowTests: XCTestCase {
    func testMissingHostFailsTestInsteadOfCrashing() throws {
      let viewController = UIViewController()

      var result: (dispose: () -> Void, usedKeyWindow: Bool)?
      XCTExpectFailure {
        result = prepareView(
          config: .init(safeArea: .zero, size: .init(width: 20, height: 20), traits: .init()),
          drawHierarchyInKeyWindow: true,
          traits: .init(),
          view: viewController.view,
          viewController: viewController
        )
      } issueMatcher: {
        $0.compactDescription.contains(
          "'drawHierarchyInKeyWindow' requires tests to be run in a host application")
      }

      let prepared = try XCTUnwrap(result)
      XCTAssertFalse(prepared.usedKeyWindow)
      prepared.dispose()
    }

    func testMissingHostFallbackRendersWithLayerRender() throws {
      let viewController = UIViewController()
      viewController.view.backgroundColor = .red

      var image: UIImage?
      XCTExpectFailure {
        snapshotView(
          config: .init(safeArea: .zero, size: .init(width: 20, height: 20), traits: .init()),
          drawHierarchyInKeyWindow: true,
          traits: .init(),
          view: viewController.view,
          viewController: viewController
        )
        .run { image = $0 }
      } issueMatcher: {
        $0.compactDescription.contains(
          "'drawHierarchyInKeyWindow' requires tests to be run in a host application")
      }

      // The fallback must produce a real `layer.render` capture, not the all-black frame a
      // host-less `drawHierarchy` yields.
      let captured = try XCTUnwrap(image)
      XCTAssertEqual(captured.size, .init(width: 20, height: 20))
      let pixel = try XCTUnwrap(firstPixel(of: captured))
      XCTAssertGreaterThan(pixel.red, 128)
      XCTAssertLessThan(pixel.green, 128)
    }

    private func firstPixel(of image: UIImage) -> (red: UInt8, green: UInt8)? {
      guard let cgImage = image.cgImage else { return nil }
      var rgba = [UInt8](repeating: 0, count: 4)
      guard
        let context = CGContext(
          data: &rgba,
          width: 1,
          height: 1,
          bitsPerComponent: 8,
          bytesPerRow: 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { return nil }
      context.draw(cgImage, in: .init(x: 0, y: 0, width: 1, height: 1))
      return (red: rgba[0], green: rgba[1])
    }
  }
#endif
