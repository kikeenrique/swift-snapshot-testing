import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

/// Integration tests for `drawHierarchyInKeyWindow: true`.
///
/// The package's own test bundle has no host application, so it can only assert the *failure*
/// path of window-drawn captures. These tests run inside `HostApp` and cover the happy path:
/// that the render server actually composites visual effects and system chrome into the
/// captured image, and that repeated captures stay deterministic.
///
/// Every assertion here is fixture-free — no reference images are stored — so the suite survives
/// system chrome redesigns and can run on any simulator.
final class DrawHierarchyInKeyWindowTests: XCTestCase {
  override class func setUp() {
    super.setUp()
    // Window-drawn captures sample the live Core Animation timeline; disabling animations in the
    // host process keeps them deterministic.
    UIView.setAnimationsEnabled(false)
  }

  // MARK: - 1. Happy path

  /// The baseline the host application exists for: a window-drawn capture succeeds and returns
  /// the view's real pixels.
  ///
  /// The library records a test failure both when the key window is missing and when
  /// `drawHierarchy(in:afterScreenUpdates:)` reports an incomplete capture, so this test passing
  /// *is* the assertion that neither happened.
  func testDrawHierarchyInKeyWindowHappyPath() throws {
    let viewController = UIViewController()
    viewController.view.backgroundColor = .red

    let image = try capture(
      viewController,
      as: .image(drawHierarchyInKeyWindow: true, size: Self.squareSize)
    )

    XCTAssertEqual(image.size, Self.squareSize)

    let statistics = try XCTUnwrap(image.statistics())
    XCTAssertGreaterThan(statistics.red, 0.9, "expected a red capture, not a black frame")
    XCTAssertLessThan(statistics.green, 0.1)
    XCTAssertLessThan(statistics.blue, 0.1)
    XCTAssertGreaterThan(statistics.alphaCoverage, 0.99)
  }

  // MARK: - 2. SwiftUI glass

  /// SwiftUI's `glassEffect` is composited by the render server, so it is absent from a
  /// `CALayer.render(in:)` capture and present in a window-drawn one.
  ///
  /// This is the reproducer for the "Liquid Glass does not render in snapshots" reports.
  func testGlassEffectRendersOnlyWithKeyWindowDraw() throws {
    #if compiler(>=6.2)
      guard #available(iOS 26.0, *) else {
        throw XCTSkip("`glassEffect` requires iOS 26.")
      }

      let layout = SwiftUISnapshotLayout.fixed(
        width: Self.squareSize.width, height: Self.squareSize.height)

      let layerRendered = try capture(
        GlassEffectSample(), as: .image(layout: layout, traits: Self.lightMode))
      let windowDrawn = try capture(
        GlassEffectSample(),
        as: .image(drawHierarchyInKeyWindow: true, layout: layout, traits: Self.lightMode)
      )

      try assertEffectIsVisibleOnlyInWindowDrawnCapture(
        layerRendered: layerRendered, windowDrawn: windowDrawn)
    #else
      throw XCTSkip("`glassEffect` requires the iOS 26 SDK.")
    #endif
  }

  // MARK: - 3. UIKit glass

  /// The same invariant for UIKit's `UIGlassEffect` in a `UIVisualEffectView`.
  func testUIKitGlassEffectView() throws {
    #if compiler(>=6.2)
      guard #available(iOS 26.0, *) else {
        throw XCTSkip("`UIGlassEffect` requires iOS 26.")
      }

      let layerRendered = try capture(
        Self.makeUIKitGlassView(), as: .image(traits: Self.lightMode))
      let windowDrawn = try capture(
        Self.makeUIKitGlassView(),
        as: .image(drawHierarchyInKeyWindow: true, traits: Self.lightMode)
      )

      try assertEffectIsVisibleOnlyInWindowDrawnCapture(
        layerRendered: layerRendered, windowDrawn: windowDrawn)
    #else
      throw XCTSkip("`UIGlassEffect` requires the iOS 26 SDK.")
    #endif
  }

  // MARK: - 4. System chrome

  /// Navigation chrome (title, search field) is system-composited too. Host-less rendering
  /// produces a top band with no contrast — an invisible title over an empty bar. A window-drawn
  /// capture must show real content there.
  ///
  /// The assertion is intentionally loose (contrast exists) rather than pixel-exact, so that
  /// redesigns of the navigation bar do not break it.
  func testNavigationChromeIsVisible() throws {
    let image = try capture(
      NavigationSample(),
      as: .image(
        drawHierarchyInKeyWindow: true,
        layout: .fixed(width: Self.phoneSize.width, height: Self.phoneSize.height),
        traits: Self.lightMode
      )
    )

    XCTAssertEqual(image.size, Self.phoneSize)

    let topBand = try XCTUnwrap(image.statistics(in: CGRect(x: 0, y: 0, width: 1, height: 0.2)))
    XCTAssertGreaterThan(
      topBand.luminanceVariance, 0.0005,
      """
      The top band of the capture is flat: the navigation title and search field did not render. \
      This is the "white-on-white chrome" symptom of a host-less capture.
      """
    )
    XCTAssertGreaterThan(topBand.alphaCoverage, 0.99, "the chrome band should be opaque")
  }

  // MARK: - 5. Determinism

  /// Window-drawn captures sample the live render server, so they are only usable as snapshots if
  /// they are reproducible. Two back-to-back captures of a static view must diff clean under the
  /// library's own image diffing.
  func testConsecutiveCapturesAreStable() throws {
    let first: UIImage
    let second: UIImage

    #if compiler(>=6.2)
      if #available(iOS 26.0, *) {
        let layout = SwiftUISnapshotLayout.fixed(
          width: Self.squareSize.width, height: Self.squareSize.height)
        first = try capture(
          GlassEffectSample(),
          as: .image(drawHierarchyInKeyWindow: true, layout: layout, traits: Self.lightMode))
        second = try capture(
          GlassEffectSample(),
          as: .image(drawHierarchyInKeyWindow: true, layout: layout, traits: Self.lightMode))
      } else {
        (first, second) = try captureSolidColorTwice()
      }
    #else
      (first, second) = try captureSolidColorTwice()
    #endif

    let diffing = Diffing<UIImage>.image(precision: 0.995, perceptualPrecision: 0.98)
    let difference = diffing.diffV2(first, second)
    XCTAssertNil(difference?.0, "consecutive window-drawn captures were not stable")
  }

  // MARK: - Helpers

  private static let squareSize = CGSize(width: 240, height: 240)
  private static let phoneSize = CGSize(width: 393, height: 852)

  /// The region the effect under test occupies, well inside its bounds.
  private static let effectRegion = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
  /// A corner of the capture, guaranteed to show only the plain backdrop.
  private static let backdropRegion = CGRect(x: 0, y: 0, width: 0.12, height: 0.12)

  private static let lightMode = UITraitCollection { traits in
    traits.userInterfaceStyle = .light
  }

  private func captureSolidColorTwice() throws -> (UIImage, UIImage) {
    let strategy = Snapshotting<UIViewController, UIImage>.image(
      drawHierarchyInKeyWindow: true, size: Self.squareSize, traits: Self.lightMode)
    func makeViewController() -> UIViewController {
      let viewController = UIViewController()
      viewController.view.backgroundColor = .systemBlue
      return viewController
    }
    return (
      try capture(makeViewController(), as: strategy),
      try capture(makeViewController(), as: strategy)
    )
  }

  /// Asserts the shared invariant of tests 2 and 3: the effect region is blank in the layer-tree
  /// capture and materially different — and opaque — in the window-drawn capture.
  private func assertEffectIsVisibleOnlyInWindowDrawnCapture(
    layerRendered: UIImage,
    windowDrawn: UIImage,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let layerEffect = try XCTUnwrap(layerRendered.statistics(in: Self.effectRegion))
    let layerBackdrop = try XCTUnwrap(layerRendered.statistics(in: Self.backdropRegion))
    let windowEffect = try XCTUnwrap(windowDrawn.statistics(in: Self.effectRegion))
    let windowBackdrop = try XCTUnwrap(windowDrawn.statistics(in: Self.backdropRegion))

    XCTAssertEqual(
      layerRendered.size, windowDrawn.size, "both captures must be the same size", file: file,
      line: line)

    // (a) `CALayer.render(in:)` never sees the effect: the region is indistinguishable from the
    // plain backdrop behind it.
    XCTAssertLessThan(
      layerEffect.colorDistance(to: layerBackdrop), 0.05,
      """
      Expected the effect region of a layer-rendered capture to be blank. Visual effects are \
      composited out of process and are not part of the view's own layer tree.
      """,
      file: file, line: line
    )

    // (b) The window-drawn capture composites the effect: opaque, and measurably different from
    // the backdrop.
    XCTAssertGreaterThan(
      windowEffect.alphaCoverage, 0.99, "the effect region should be opaque", file: file, line: line
    )
    XCTAssertGreaterThan(
      windowEffect.colorDistance(to: windowBackdrop), 0.05,
      "the effect region did not differ from the backdrop: the effect did not render",
      file: file, line: line
    )

    // And the two captures disagree over a real part of the region, not a stray pixel.
    let differing = try XCTUnwrap(
      windowDrawn.fractionOfPixelsDiffering(from: layerRendered, in: Self.effectRegion))
    XCTAssertGreaterThan(
      differing, 0.1,
      "the window-drawn and layer-rendered captures were nearly identical in the effect region",
      file: file, line: line
    )
  }

  #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private static func makeUIKitGlassView() -> UIView {
      let container = UIView(frame: CGRect(origin: .zero, size: squareSize))
      container.backgroundColor = .systemBlue

      let effectView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
      effectView.frame = CGRect(
        x: squareSize.width * 0.25,
        y: squareSize.height * 0.25,
        width: squareSize.width * 0.5,
        height: squareSize.height * 0.5
      )
      container.addSubview(effectView)
      return container
    }
  #endif

  /// Runs a snapshot strategy and returns the image it produced.
  ///
  /// This uses only public API — `Snapshotting.snapshot` — instead of `assertSnapshot`, so that
  /// no reference images are ever written to disk.
  private func capture<Value>(
    _ value: Value,
    as strategy: Snapshotting<Value, UIImage>,
    timeout: TimeInterval = 10,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws -> UIImage {
    var result: UIImage?
    let finished = expectation(description: "snapshot")
    strategy.snapshot(value).run { image in
      result = image
      finished.fulfill()
    }
    wait(for: [finished], timeout: timeout)
    return try XCTUnwrap(result, "the strategy produced no image", file: file, line: line)
  }
}

// MARK: - Views under test

#if compiler(>=6.2)
  @available(iOS 26.0, *)
  private struct GlassEffectSample: View {
    var body: some View {
      ZStack {
        Color.blue
        Color.clear
          .frame(width: 120, height: 120)
          .glassEffect(.regular, in: .rect(cornerRadius: 24))
      }
    }
  }
#endif

private struct NavigationSample: View {
  @State private var query = ""

  var body: some View {
    NavigationStack {
      List {
        ForEach(0..<12, id: \.self) { index in
          Text("Row \(index)")
        }
      }
      .navigationTitle("Snapshots")
      .searchable(text: $query)
    }
  }
}
