import Foundation
import XCTest

@testable import SnapshotTesting

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif
#if canImport(SceneKit)
  import SceneKit
#endif
#if canImport(SpriteKit)
  import SpriteKit
  import SwiftUI
#endif
#if canImport(WebKit)
  @preconcurrency import WebKit
#endif
#if canImport(UIKit)
  import UIKit.UIView
#endif

#if os(visionOS)
  // visionOS resolves dynamic colors as dark appearance by default, which renders the
  // default label color white — invisible against these shared fixtures' light
  // backgrounds. The visionOS image snapshots pin light appearance so the fixtures
  // resolve the same dynamic colors as the iOS device configs.
  private let visionOSLightTraits = UITraitCollection(userInterfaceStyle: .light)
#endif

// Timeout for the web view assertions. On visionOS the generous value absorbs the one-off WebKit
// content process startup, which can exceed the default 5 seconds on a cold simulator. Every
// other platform keeps the default so a hung web view fails fast.
//
// visionOS also rasterizes the fixture's SVG logo nondeterministically: repeated runs of an
// unchanged page alternate between two results that differ by a single 1/255 step on 18 of the
// image's 1.9M pixels. Comparing those snapshots perceptually absorbs the noise while still
// failing on any difference a person could see.
#if os(visionOS)
  private let webViewTimeout: TimeInterval = 30
  private let webViewPerceptualPrecision: Float = 0.98
#else
  private let webViewTimeout: TimeInterval = 5
  private let webViewPerceptualPrecision: Float = 1
#endif

final class SnapshotTestingTests: BaseTestCase {
  func testAny() {
    struct User { let id: Int, name: String, bio: String }
    let user = User(id: 1, name: "Blobby", bio: "Blobbed around the world.")
    assertSnapshot(of: user, as: .dump)
  }

  func testRecursion() {
    withSnapshotTesting {
      class Father {
        var child: Child?
        init(_ child: Child? = nil) { self.child = child }
      }
      class Child {
        let father: Father
        init(_ father: Father) {
          self.father = father
          father.child = self
        }
      }
      let father = Father()
      let child = Child(father)
      assertSnapshot(of: father, as: .dump)
      assertSnapshot(of: child, as: .dump)
    }
  }

  @available(macOS 10.13, tvOS 11.0, *)
  func testAnyAsJson() throws {
    struct User: Encodable { let id: Int, name: String, bio: String }
    let user = User(id: 1, name: "Blobby", bio: "Blobbed around the world.")

    let data = try JSONEncoder().encode(user)
    let any = try JSONSerialization.jsonObject(with: data, options: [])

    assertSnapshot(of: any, as: .json)
  }

  func testAnySnapshotStringConvertible() {
    assertSnapshot(of: "a" as Character, as: .dump, named: "character")
    assertSnapshot(of: Data("Hello, world!".utf8), as: .dump, named: "data")
    assertSnapshot(of: Date(timeIntervalSinceReferenceDate: 0), as: .dump, named: "date")
    assertSnapshot(of: NSObject(), as: .dump, named: "nsobject")
    assertSnapshot(of: "Hello, world!", as: .dump, named: "string")
    assertSnapshot(of: "Hello, world!".dropLast(8), as: .dump, named: "substring")
    assertSnapshot(of: URL(string: "https://www.pointfree.co")!, as: .dump, named: "url")
  }

  func testAutolayout() {
    #if os(iOS) || os(visionOS)
      let vc = UIViewController()
      vc.view.translatesAutoresizingMaskIntoConstraints = false
      let subview = UIView()
      subview.translatesAutoresizingMaskIntoConstraints = false
      vc.view.addSubview(subview)
      NSLayoutConstraint.activate([
        subview.topAnchor.constraint(equalTo: vc.view.topAnchor),
        subview.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
        subview.leftAnchor.constraint(equalTo: vc.view.leftAnchor),
        subview.rightAnchor.constraint(equalTo: vc.view.rightAnchor),
      ])
      assertSnapshot(of: vc, as: .image, named: visionOSSuffix)
    #endif
  }

  func testDeterministicDictionaryAndSetSnapshots() {
    struct Person: Hashable { let name: String }
    struct DictionarySetContainer { let dict: [String: Int], set: Set<Person> }
    let set = DictionarySetContainer(
      dict: ["c": 3, "a": 1, "b": 2],
      set: [.init(name: "Brandon"), .init(name: "Stephen")]
    )
    assertSnapshot(of: set, as: .dump)
  }

  func testCaseIterable() {
    enum Direction: String, CaseIterable {
      case up, down, left, right
      var rotatedLeft: Direction {
        switch self {
        case .up: return .left
        case .down: return .right
        case .left: return .down
        case .right: return .up
        }
      }
    }

    assertSnapshot(
      of: { $0.rotatedLeft },
      as: Snapshotting<Direction, String>.func(into: .description)
    )
  }

  func testCGPath() {
    #if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
      let path = CGPath.heart

      let osName: String
      #if os(iOS)
        osName = "iOS"
      #elseif os(tvOS)
        osName = "tvOS"
      #elseif os(macOS)
        osName = "macOS"
      #elseif os(visionOS)
        osName = "visionOS"
      #endif

      if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
        #if os(macOS)
          // Pin scale so the reference is portable across recording hosts. Other platforms keep
          // their existing references.
          assertSnapshot(of: path, as: .image(scale: 2), named: osName)
        #else
          assertSnapshot(of: path, as: .image, named: osName)
        #endif
      }

      if #available(iOS 11.0, OSX 10.13, tvOS 11.0, *) {
        assertSnapshot(of: path, as: .elementsDescription, named: osName)
      }
    #endif
  }

  func testData() {
    let data = Data([0xDE, 0xAD, 0xBE, 0xEF])

    assertSnapshot(of: data, as: .data)
  }

  func testEncodable() {
    struct User: Encodable { let id: Int, name: String, bio: String }
    let user = User(id: 1, name: "Blobby", bio: "Blobbed around the world.")

    if #available(iOS 11.0, macOS 10.13, tvOS 11.0, *) {
      assertSnapshot(of: user, as: .json)
    }
    assertSnapshot(of: user, as: .plist)
  }

  func testMixedViews() {
    //    #if os(iOS) || os(macOS)
    //    // NB: CircleCI crashes while trying to instantiate SKView.
    //    if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
    //      let webView = WKWebView(frame: .init(x: 0, y: 0, width: 50, height: 50))
    //      webView.loadHTMLString("🌎", baseURL: nil)
    //
    //      let skView = SKView(frame: .init(x: 50, y: 0, width: 50, height: 50))
    //      let scene = SKScene(size: .init(width: 50, height: 50))
    //      let node = SKShapeNode(circleOfRadius: 15)
    //      node.fillColor = .red
    //      node.position = .init(x: 25, y: 25)
    //      scene.addChild(node)
    //      skView.presentScene(scene)
    //
    //      let view = View(frame: .init(x: 0, y: 0, width: 100, height: 50))
    //      view.addSubview(webView)
    //      view.addSubview(skView)
    //
    //      assertSnapshot(of: view, as: .image, named: platform)
    //    }
    //    #endif
  }

  func testMultipleSnapshots() {
    assertSnapshot(of: [1], as: .dump)
    assertSnapshot(of: [1, 2], as: .dump)
  }

  func testNamedAssertion() {
    struct User { let id: Int, name: String, bio: String }
    let user = User(id: 1, name: "Blobby", bio: "Blobbed around the world.")
    assertSnapshot(of: user, as: .dump, named: "named")
  }

  func testNSBezierPath() {
    #if os(macOS)
      let path = NSBezierPath.heart

      if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
        assertSnapshot(of: path, as: .image(scale: 2), named: "macOS")
      }

      assertSnapshot(of: path, as: .elementsDescription, named: "macOS")
    #endif
  }

  func testNSView() {
    #if os(macOS)
      let button = NSButton()
      button.bezelStyle = .rounded
      button.title = "Push Me"
      button.sizeToFit()
      if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
        // Text glyph antialiasing differs across macOS point releases, so allow a small
        // perceptual tolerance on top of the pinned scale.
        // Pin the appearance: an unpinned render follows the recording machine's system setting,
        // and recorded in dark mode this button's title is drawn light on a light control, which
        // produced a reference with no visible text at all.
        assertSnapshot(
          of: button,
          as: .lightImage(perceptualPrecision: 0.98))
        assertSnapshot(of: button, as: .recursiveDescription)
      }
    #endif
  }

  func testNSViewWithLayer() {
    #if os(macOS)
      let view = NSView()
      view.frame = CGRect(x: 0.0, y: 0.0, width: 10.0, height: 10.0)
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.green.cgColor
      view.layer?.cornerRadius = 5
      if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
        assertSnapshot(of: view, as: .image(scale: 2))
        assertSnapshot(of: view, as: .recursiveDescription)
        assertSnapshot(
          of: view, as: .image(size: CGSize(width: 30.0, height: 10.0), scale: 2),
          named: "size-override")
      }
    #endif
  }

  func testNSViewController() {
    #if os(macOS)
      let viewController = NSViewController()
      let view = NSView()
      view.frame = CGRect(x: 0.0, y: 0.0, width: 20.0, height: 20.0)
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.orange.cgColor
      view.layer?.cornerRadius = 10
      viewController.view = view
      assertSnapshot(of: viewController, as: .image(scale: 2))
      assertSnapshot(of: viewController, as: .recursiveDescription)
      assertSnapshot(
        of: viewController, as: .image(size: CGSize(width: 40.0, height: 10.0), scale: 2),
        named: "size-override")
    #endif
  }

  func testNSViewAppearance() {
    #if os(macOS)
      // Draws with a dynamic system color, which resolves against the effective appearance at
      // draw time — so the light and dark renders must differ.
      final class AppearanceView: NSView {
        override func draw(_ dirtyRect: NSRect) {
          NSColor.windowBackgroundColor.setFill()
          bounds.fill()
        }
      }
      let view = AppearanceView(frame: CGRect(x: 0.0, y: 0.0, width: 20.0, height: 20.0))
      assertSnapshot(
        of: view, as: .image(appearance: NSAppearance(named: .aqua), scale: 2), named: "light")
      assertSnapshot(
        of: view, as: .image(appearance: NSAppearance(named: .darkAqua), scale: 2), named: "dark")

      let viewController = NSViewController()
      viewController.view = AppearanceView(
        frame: CGRect(x: 0.0, y: 0.0, width: 20.0, height: 20.0))
      assertSnapshot(
        of: viewController, as: .image(appearance: NSAppearance(named: .darkAqua), scale: 2),
        named: "view-controller-dark")
    #endif
  }

  func testNSViewScale() {
    #if os(macOS)
      let view = NSView()
      view.frame = CGRect(x: 0.0, y: 0.0, width: 10.0, height: 10.0)
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.blue.cgColor
      view.layer?.cornerRadius = 5
      // Pinned scales render machine-independently: 10 pt becomes 10 px at 1x, 20 px at 2x,
      // regardless of the host display's backing scale.
      assertSnapshot(of: view, as: .image(scale: 1), named: "1x")
      assertSnapshot(of: view, as: .image(scale: 2), named: "2x")
    #endif
  }

  func testNSViewRendersAtPinnedScale() {
    #if os(macOS)
      // A windowless view has a 1x backing scale, so `cacheDisplay(in:to:)` used to rasterize at
      // 1x and stretch into the 2x rep (blurry references). The pinned-scale branch must instead
      // rasterize at the requested scale.
      final class ScaleReportingView: NSView {
        var renderedScale: CGFloat = 0
        override func draw(_ dirtyRect: NSRect) {
          renderedScale = NSGraphicsContext.current?.cgContext.ctm.a ?? 0
          NSColor.white.setFill()
          dirtyRect.fill()
        }
      }

      func render(scale: CGFloat) -> (renderedScale: CGFloat, image: NSImage) {
        let view = ScaleReportingView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        var image: NSImage!
        Snapshotting<NSView, NSImage>.image(scale: scale).snapshot(view).run { image = $0 }
        return (view.renderedScale, image)
      }

      let (scale1, image1) = render(scale: 1)
      XCTAssertEqual(scale1, 1)
      XCTAssertEqual(image1.representations[0].pixelsWide, 10)

      let (scale2, image2) = render(scale: 2)
      XCTAssertEqual(scale2, 2)
      XCTAssertEqual(image2.representations[0].pixelsWide, 20)
    #endif
  }

  func testNSViewControlRendersContentAtPinnedScale() {
    #if os(macOS)
      // AppKit controls only draw through the window-backed render path — a context-only
      // approach silently produces an empty bitmap. Guard that a windowless control still
      // renders real content at a pinned scale.
      let button = NSButton()
      button.bezelStyle = .rounded
      button.title = "Push Me"
      button.sizeToFit()

      var image: NSImage!
      Snapshotting<NSView, NSImage>.image(scale: 2).snapshot(button).run { image = $0 }

      let rep = image.representations[0] as! NSBitmapImageRep
      XCTAssertEqual(CGFloat(rep.pixelsWide), button.bounds.width * 2)
      XCTAssertEqual(CGFloat(rep.pixelsHigh), button.bounds.height * 2)

      var uniqueColors: Set<UInt32> = []
      for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
          guard let color = rep.colorAt(x: x, y: y) else { continue }
          uniqueColors.insert(
            UInt32(color.redComponent * 255) << 24 | UInt32(color.greenComponent * 255) << 16
              | UInt32(color.blueComponent * 255) << 8 | UInt32(color.alphaComponent * 255)
          )
        }
      }
      XCTAssertGreaterThan(
        uniqueColors.count, 10, "Expected bezel and antialiased text, got a near-uniform bitmap"
      )
    #endif
  }

  func testNSViewInWindowRendersAtPinnedScale() {
    #if os(macOS)
      // A view already hosted in a window is temporarily re-hosted at the pinned scale and fully
      // restored, so a pinned-scale render is byte-identical to the same view rendered detached —
      // regardless of the original window's backing scale (1x here, mimicking a headless CI
      // runner; the same holds on a Retina host).
      final class OneXWindow: NSWindow {
        override var backingScaleFactor: CGFloat { 1 }
      }

      func makeLabel() -> NSView {
        let label = NSTextField(labelWithString: "Push Me")
        label.frame = CGRect(x: 0, y: 0, width: 80, height: 20)
        return label
      }
      func render(_ view: NSView) -> Data {
        var image: NSImage!
        Snapshotting<NSView, NSImage>.image(scale: 2).snapshot(view).run { image = $0 }
        return image.tiffRepresentation!
      }

      let detached = render(makeLabel())

      let hosted = makeLabel()
      let window = OneXWindow(
        contentRect: hosted.bounds, styleMask: [.borderless], backing: .buffered, defer: false
      )
      window.isReleasedWhenClosed = false
      window.contentView = hosted
      let inWindow = render(hosted)

      XCTAssertEqual(inWindow, detached)
      XCTAssertTrue(hosted.window === window, "view must be restored to its original window")

      window.contentView = nil
    #endif
  }

  func testNSViewUnderConstraintsIsRestoredAfterPinnedScale() {
    #if os(macOS)
      // Detaching the view for the pinned-scale render deactivates every constraint its ancestors
      // hold against it. Restoration must reinstate the hierarchy position, the frame, the
      // autoresizing-translation flag, and the *same* constraint objects — so that a fresh layout
      // pass still resolves to the pre-snapshot geometry instead of corrupting the next assertion.
      let root = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
      root.wantsLayer = true
      root.layer?.backgroundColor = NSColor.white.cgColor

      let container = NSView()
      container.wantsLayer = true
      container.layer?.backgroundColor = NSColor.gray.cgColor
      container.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(container)

      let view = NSView()
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.blue.cgColor
      view.translatesAutoresizingMaskIntoConstraints = false
      container.addSubview(view)

      let containerConstraints = [
        container.topAnchor.constraint(equalTo: root.topAnchor),
        container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
        container.widthAnchor.constraint(equalToConstant: 120),
        container.heightAnchor.constraint(equalToConstant: 80),
      ]
      // Size and position constraints referencing the view, held by its superview...
      let superviewConstraints = [
        view.widthAnchor.constraint(equalToConstant: 40),
        view.heightAnchor.constraint(equalToConstant: 20),
        view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
      ]
      // ...and one held by a grandparent, which the save loop only finds because it walks *all*
      // ancestors rather than just the immediate superview.
      let grandparentConstraint = view.topAnchor.constraint(equalTo: root.topAnchor, constant: 15)
      let viewConstraints = superviewConstraints + [grandparentConstraint]
      NSLayoutConstraint.activate(containerConstraints + viewConstraints)

      let window = NSWindow(
        contentRect: root.bounds, styleMask: [.borderless], backing: .buffered, defer: false
      )
      window.isReleasedWhenClosed = false
      window.contentView = root
      root.layoutSubtreeIfNeeded()

      let originalFrame = view.frame
      XCTAssertEqual(originalFrame.size, CGSize(width: 40, height: 20))

      var image: NSImage!
      Snapshotting<NSView, NSImage>.image(scale: 2).snapshot(view).run { image = $0 }
      XCTAssertEqual(image.representations[0].pixelsWide, 80)
      XCTAssertEqual(image.representations[0].pixelsHigh, 40)

      XCTAssertTrue(view.superview === container, "superview identity must be restored")
      XCTAssertEqual(container.subviews.firstIndex(of: view), 0, "subview index must be restored")
      XCTAssertTrue(view.window === window, "the view must be back in its original window")
      XCTAssertEqual(view.frame, originalFrame, "frame must be restored")
      XCTAssertFalse(
        view.translatesAutoresizingMaskIntoConstraints,
        "the offscreen window sets translatesAutoresizingMaskIntoConstraints; it must be restored"
      )

      // Every constraint referencing the view is still installed and active — compared by object
      // identity, not by count, so a "restoration" that installed equivalent replacements would
      // still fail. The walk starts at the view itself because AppKit installs a self-sizing
      // constraint (`view.width == 40`) on the view, not on an ancestor.
      var installed: Set<ObjectIdentifier> = []
      var ancestor: NSView? = view
      while let current = ancestor {
        for constraint in current.constraints { installed.insert(ObjectIdentifier(constraint)) }
        ancestor = current.superview
      }
      for constraint in viewConstraints {
        XCTAssertTrue(
          installed.contains(ObjectIdentifier(constraint)),
          "constraint \(constraint) was not reinstalled on an ancestor"
        )
        XCTAssertTrue(constraint.isActive, "constraint \(constraint) was left inactive")
      }

      // The decisive check: the constraints still *drive* the layout to the same geometry.
      root.layoutSubtreeIfNeeded()
      XCTAssertEqual(
        view.frame, originalFrame, "layout must still resolve to the pre-snapshot frame"
      )

      window.contentView = nil
    #endif
  }

  func testNSViewInStackViewIsRestoredAfterPinnedScale() {
    #if os(macOS)
      // `NSStackView` tracks its children in `arrangedSubviews`, which a naive
      // superview/index restoration re-adds as a plain subview only. Snapshotting an arranged
      // subview must leave the stack laying out exactly as it did before.
      func makeBox(_ color: NSColor) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = color.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 20).isActive = true
        box.heightAnchor.constraint(equalToConstant: 10).isActive = true
        return box
      }

      let boxes = [makeBox(.red), makeBox(.green), makeBox(.blue)]
      let stack = NSStackView(views: boxes)
      stack.orientation = .horizontal
      stack.spacing = 4
      stack.frame = CGRect(x: 0, y: 0, width: 100, height: 40)

      let window = NSWindow(
        contentRect: stack.bounds, styleMask: [.borderless], backing: .buffered, defer: false
      )
      window.isReleasedWhenClosed = false
      window.contentView = stack
      stack.layoutSubtreeIfNeeded()

      let framesBefore = boxes.map(\.frame)
      let target = boxes[1]

      var image: NSImage!
      Snapshotting<NSView, NSImage>.image(scale: 2).snapshot(target).run { image = $0 }
      XCTAssertEqual(image.representations[0].pixelsWide, 40)

      XCTAssertTrue(target.superview === stack, "superview identity must be restored")
      // Containment alone is not enough: the stack must still be managing the view, at the same
      // arranged position it held before the snapshot.
      XCTAssertEqual(
        stack.arrangedSubviews.firstIndex(of: target), 1,
        "the view must be restored as an arranged subview at its original position"
      )

      stack.layoutSubtreeIfNeeded()
      XCTAssertEqual(
        boxes.map(\.frame), framesBefore, "the stack must lay its children out identically"
      )

      window.contentView = nil
    #endif
  }

  func testNSViewInWindowConsecutivePinnedScaleSnapshotsAreIdentical() {
    #if os(macOS)
      // The restoration round-trip must leave no residue: snapshotting the same in-window view
      // twice back-to-back has to produce byte-identical PNGs, not merely similar-looking ones.
      let view = NSView(frame: CGRect(x: 0, y: 0, width: 30, height: 20))
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.blue.cgColor
      let inner = NSView(frame: CGRect(x: 5, y: 5, width: 10, height: 10))
      inner.wantsLayer = true
      inner.layer?.backgroundColor = NSColor.red.cgColor
      view.addSubview(inner)

      let window = NSWindow(
        contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false
      )
      window.isReleasedWhenClosed = false
      window.contentView = view

      func renderPNG() -> Data {
        var image: NSImage!
        Snapshotting<NSView, NSImage>.image(scale: 2).snapshot(view).run { image = $0 }
        let rep = image.representations[0] as! NSBitmapImageRep
        XCTAssertEqual(rep.pixelsWide, 60)
        XCTAssertEqual(rep.pixelsHigh, 40)
        return rep.representation(using: .png, properties: [:])!
      }

      let first = renderPNG()
      let second = renderPNG()
      XCTAssertEqual(
        first, second, "a second pinned-scale render must be byte-identical to the first"
      )

      window.contentView = nil
    #endif
  }

  func testNSViewInWindowRecursiveDescriptionSurvivesPinnedScaleSnapshot() {
    #if os(macOS)
      // Detaching the view dirties layout flags across its subtree; if they are not settled back
      // down, the residue shows up as changed frames in a later `recursiveDescription` snapshot.
      let view = NSView(frame: CGRect(x: 0, y: 0, width: 40, height: 24))
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.blue.cgColor
      let inner = NSView(frame: CGRect(x: 4, y: 4, width: 12, height: 12))
      inner.wantsLayer = true
      inner.layer?.backgroundColor = NSColor.red.cgColor
      view.addSubview(inner)

      let window = NSWindow(
        contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false
      )
      window.isReleasedWhenClosed = false
      window.contentView = view

      func describe() -> String {
        var description: String!
        Snapshotting<NSView, String>.recursiveDescription.snapshot(view).run { description = $0 }
        return description
      }

      // Settle layout first, so the "before" string records a clean subtree: anything the image
      // snapshot leaves dirty (an `L`/`l` needsLayout flag, a moved frame) then shows up as a
      // difference rather than being masked by pre-existing dirt.
      view.layoutSubtreeIfNeeded()
      let before = describe()
      var image: NSImage!
      Snapshotting<NSView, NSImage>.image(scale: 2).snapshot(view).run { image = $0 }
      XCTAssertEqual(image.representations[0].pixelsWide, 80)
      let after = describe()

      XCTAssertEqual(
        before, after, "a pinned-scale image snapshot must not perturb the recursive description"
      )

      window.contentView = nil
    #endif
  }

  func testNSViewZeroSizeFailsInsteadOfCrashing() {
    #if os(macOS)
      // A view that cannot be rendered is a per-assertion input problem, not a reason to take the
      // whole test process down: it must surface as one ordinary failure, write no reference, and
      // leave the process healthy for everything that follows.
      let zeroSized = NSView(frame: .zero)

      let failure = verifySnapshot(of: zeroSized, as: .image(scale: 2), named: "zeroSize")
      XCTAssertNotNil(failure)
      XCTAssertTrue(
        failure?.contains("not renderable") == true,
        "Expected an actionable diagnosis, got: \(failure ?? "nil")"
      )

      // The same input through the reporting path fails the test rather than crashing.
      XCTExpectFailure("A zero-sized view is expected to fail its own assertion") {
        assertSnapshot(of: NSView(frame: .zero), as: .image(scale: 2), named: "zeroSize")
      }

      // No reference is ever written for a diagnosed failure, in any record mode: the diagnostic
      // is returned before both the comparison and the recording branch.
      let referenceUrl = URL(fileURLWithPath: String(#file), isDirectory: false)
        .deletingLastPathComponent()
        .appendingPathComponent("__Snapshots__")
        .appendingPathComponent("SnapshotTestingTests")
        .appendingPathComponent("testNSViewZeroSizeFailsInsteadOfCrashing.zeroSize.png")
      XCTAssertFalse(
        FileManager.default.fileExists(atPath: referenceUrl.path),
        "No reference should be recorded for a view that could not be rendered"
      )

      // The process — and the next assertion — survive.
      let renderable = NSView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
      renderable.wantsLayer = true
      renderable.layer?.backgroundColor = NSColor.blue.cgColor
      var image: NSImage!
      Snapshotting<NSView, NSImage>.image(scale: 2).snapshot(renderable).run { image = $0 }
      XCTAssertEqual(image.representations[0].pixelsWide, 20)
      XCTAssertEqual(image.representations[0].pixelsHigh, 20)
    #endif
  }

  func testNSHostingController() {
    #if os(macOS)
      // Shapes in explicit colors rather than an SF Symbol and Text: what this asserts is the
      // hosting strategy's own behavior (size override, pinned scale), and system glyphs, symbols,
      // and semantic colors like Color.yellow are drawn by the OS, so their rasterization moves
      // between releases and the reference stops being portable.
      let controller = NSHostingController(
        rootView: swiftUIProbe.background(Color(red: 1.0, green: 0.8, blue: 0.0)))
      assertSnapshot(
        of: controller,
        as: .image(perceptualPrecision: 0.98, size: CGSize(width: 200.0, height: 100.0), scale: 2)
      )
    #endif
  }

  func testPrecision() {
    #if os(iOS) || os(macOS) || os(tvOS) || os(visionOS)
      #if os(iOS) || os(tvOS) || os(visionOS)
        let label = UILabel()
        #if os(iOS)
          label.frame = CGRect(origin: .zero, size: CGSize(width: 43.5, height: 20.5))
        #elseif os(tvOS)
          label.frame = CGRect(origin: .zero, size: CGSize(width: 98, height: 46))
        #elseif os(visionOS)
          label.frame = CGRect(origin: .zero, size: CGSize(width: 43.5, height: 20.5))
        #endif
        label.backgroundColor = .white
      #elseif os(macOS)
        let label = NSTextField()
        label.frame = CGRect(origin: .zero, size: CGSize(width: 37, height: 16))
        label.backgroundColor = .white
        label.isBezeled = false
        label.isEditable = false
      #endif
      if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
        #if os(visionOS)
          // Without pinned light appearance the label text would render white on this
          // white background, making the precision comparison vacuous.
          let strategy: Snapshotting<UIView, UIImage> = .image(
            precision: 0.9, traits: visionOSLightTraits)
        #elseif os(macOS)
          let strategy: Snapshotting<NSView, NSImage> = .lightImage(
            precision: 0.9, perceptualPrecision: 0.98)
        #else
          let strategy: Snapshotting<UIView, UIImage> = .image(precision: 0.9)
        #endif
        label.text = "Hello."
        assertSnapshot(of: label, as: strategy, named: platform)
        label.text = "Hello"
        assertSnapshot(of: label, as: strategy, named: platform)
      }
    #endif
  }

  func testImagePrecision() throws {
    #if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
      let imageURL = URL(fileURLWithPath: String(#file), isDirectory: false)
        .deletingLastPathComponent()
        .appendingPathComponent("__Fixtures__/testImagePrecision.reference.png")
      #if os(iOS) || os(tvOS) || os(visionOS)
        let image = try XCTUnwrap(UIImage(contentsOfFile: imageURL.path))
      #elseif os(macOS)
        let image = try XCTUnwrap(NSImage(byReferencing: imageURL))
      #endif

      assertSnapshot(of: image, as: .image(precision: 0.995), named: "exact")
      if #available(iOS 11.0, tvOS 11.0, macOS 10.13, *) {
        assertSnapshot(of: image, as: .image(perceptualPrecision: 0.98), named: "perceptual")
      }
    #endif
  }

  func testSCNView() {
    // #if os(iOS) || os(macOS) || os(tvOS)
    // // NB: CircleCI crashes while trying to instantiate SCNView.
    // if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
    //   let scene = SCNScene()
    //
    //   let sphereGeometry = SCNSphere(radius: 3)
    //   sphereGeometry.segmentCount = 200
    //   let sphereNode = SCNNode(geometry: sphereGeometry)
    //   sphereNode.position = SCNVector3Zero
    //   scene.rootNode.addChildNode(sphereNode)
    //
    //   sphereGeometry.firstMaterial?.diffuse.contents = URL(fileURLWithPath: String(#file), isDirectory: false)
    //     .deletingLastPathComponent()
    //     .appendingPathComponent("__Fixtures__/earth.png")
    //
    //   let cameraNode = SCNNode()
    //   cameraNode.camera = SCNCamera()
    //   cameraNode.position = SCNVector3Make(0, 0, 8)
    //   scene.rootNode.addChildNode(cameraNode)
    //
    //   let omniLight = SCNLight()
    //   omniLight.type = .omni
    //   let omniLightNode = SCNNode()
    //   omniLightNode.light = omniLight
    //   omniLightNode.position = SCNVector3Make(10, 10, 10)
    //   scene.rootNode.addChildNode(omniLightNode)
    //
    //   assertSnapshot(
    //     of: scene,
    //     as: .image(size: .init(width: 500, height: 500)),
    //     named: platform
    //   )
    // }
    // #endif
  }

  func testSKView() {
    // #if os(iOS) || os(macOS) || os(tvOS)
    // // NB: CircleCI crashes while trying to instantiate SKView.
    // if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
    //   let scene = SKScene(size: .init(width: 50, height: 50))
    //   let node = SKShapeNode(circleOfRadius: 15)
    //   node.fillColor = .red
    //   node.position = .init(x: 25, y: 25)
    //   scene.addChild(node)
    //
    //   assertSnapshot(
    //     of: scene,
    //     as: .image(size: .init(width: 50, height: 50)),
    //     named: platform
    //   )
    // }
    // #endif
  }

  func testTableViewController() {
    #if os(iOS) || os(visionOS)
      class TableViewController: UITableViewController {
        override func viewDidLoad() {
          super.viewDidLoad()
          self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        }
        override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
        {
          return 10
        }
        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
          -> UITableViewCell
        {
          let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
          cell.textLabel?.text = "\(indexPath.row)"
          return cell
        }
      }
      let tableViewController = TableViewController()
      #if os(visionOS)
        // A single geometry suffices here: at narrower window widths the render is the same
        // full-width rows at a smaller width (verified empirically at 480 pt), so extra
        // window-size variants would add fixtures without adding coverage.
        assertSnapshot(
          of: tableViewController,
          as: .image(on: .visionOSWindow, traits: visionOSLightTraits),
          named: "visionos")
      #else
        assertSnapshot(of: tableViewController, as: .image(on: .iPhoneSe))
      #endif
    #endif
  }

  func testAssertMultipleSnapshot() {
    #if os(iOS) || os(visionOS)
      class TableViewController: UITableViewController {
        override func viewDidLoad() {
          super.viewDidLoad()
          self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        }
        override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
        {
          return 10
        }
        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath)
          -> UITableViewCell
        {
          let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
          cell.textLabel?.text = "\(indexPath.row)"
          return cell
        }
      }
      let tableViewController = TableViewController()
      #if os(visionOS)
        // visionOS has a single, resizable window rather than fixed device screens, so exercise
        // the multi-snapshot API with the window preset and a fixed size instead of device
        // configs. The unnamed (indexed) variant cannot run here: unnamed references are
        // written as `<test>.1.png`/`<test>.2.png` with no way to inject a platform suffix,
        // so running it on visionOS would clobber the iOS fixtures of the same name.
        assertSnapshots(
          of: tableViewController,
          as: [
            "window-visionos": .image(on: .visionOSWindow, traits: visionOSLightTraits),
            "fixed-visionos": .image(
              size: .init(width: 640, height: 480), traits: visionOSLightTraits),
          ])
      #else
        assertSnapshots(
          of: tableViewController,
          as: ["iPhoneSE-image": .image(on: .iPhoneSe), "iPad-image": .image(on: .iPadMini)])
        assertSnapshots(
          of: tableViewController, as: [.image(on: .iPhoneX), .image(on: .iPhoneXsMax)])
      #endif
    #endif
  }

  func testTraits() {
    #if os(iOS) || os(tvOS) || os(visionOS)
      if #available(iOS 11.0, tvOS 11.0, *) {
        class MyViewController: UIViewController {
          let topLabel = UILabel()
          let leadingLabel = UILabel()
          let trailingLabel = UILabel()
          let bottomLabel = UILabel()

          override func viewDidLoad() {
            super.viewDidLoad()

            self.navigationItem.leftBarButtonItem = .init(
              barButtonSystemItem: .add, target: nil, action: nil)

            self.view.backgroundColor = .white

            self.topLabel.text = "What's"
            self.leadingLabel.text = "the"
            self.trailingLabel.text = "point"
            self.bottomLabel.text = "?"

            self.topLabel.translatesAutoresizingMaskIntoConstraints = false
            self.leadingLabel.translatesAutoresizingMaskIntoConstraints = false
            self.trailingLabel.translatesAutoresizingMaskIntoConstraints = false
            self.bottomLabel.translatesAutoresizingMaskIntoConstraints = false

            self.view.addSubview(self.topLabel)
            self.view.addSubview(self.leadingLabel)
            self.view.addSubview(self.trailingLabel)
            self.view.addSubview(self.bottomLabel)

            NSLayoutConstraint.activate([
              self.topLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
              self.topLabel.centerXAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
              self.leadingLabel.leadingAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
              self.leadingLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: self.view.safeAreaLayoutGuide.centerXAnchor),
              //            self.leadingLabel.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
              self.leadingLabel.centerYAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.centerYAnchor),
              self.trailingLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.centerXAnchor),
              self.trailingLabel.trailingAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.trailingAnchor),
              self.trailingLabel.centerYAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.centerYAnchor),
              self.bottomLabel.bottomAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
              self.bottomLabel.centerXAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            ])
          }

          override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            self.topLabel.font = .preferredFont(
              forTextStyle: .headline, compatibleWith: self.traitCollection)
            self.leadingLabel.font = .preferredFont(
              forTextStyle: .body, compatibleWith: self.traitCollection)
            self.trailingLabel.font = .preferredFont(
              forTextStyle: .body, compatibleWith: self.traitCollection)
            self.bottomLabel.font = .preferredFont(
              forTextStyle: .subheadline, compatibleWith: self.traitCollection)
            self.view.setNeedsUpdateConstraints()
            self.view.updateConstraintsIfNeeded()
          }
        }

        let viewController = MyViewController()

        #if os(iOS)
          assertSnapshot(of: viewController, as: .image(on: .iPhoneSe), named: "iphone-se")
          assertSnapshot(of: viewController, as: .image(on: .iPhone8), named: "iphone-8")
          assertSnapshot(of: viewController, as: .image(on: .iPhone8Plus), named: "iphone-8-plus")
          assertSnapshot(of: viewController, as: .image(on: .iPhoneX), named: "iphone-x")
          assertSnapshot(of: viewController, as: .image(on: .iPhoneXr), named: "iphone-xr")
          assertSnapshot(of: viewController, as: .image(on: .iPhoneXsMax), named: "iphone-xs-max")
          assertSnapshot(of: viewController, as: .image(on: .iPadMini), named: "ipad-mini")
          assertSnapshot(of: viewController, as: .image(on: .iPad9_7), named: "ipad-9-7")
          assertSnapshot(of: viewController, as: .image(on: .iPad10_2), named: "ipad-10-2")
          assertSnapshot(of: viewController, as: .image(on: .iPadPro10_5), named: "ipad-pro-10-5")
          assertSnapshot(of: viewController, as: .image(on: .iPadPro11), named: "ipad-pro-11")
          assertSnapshot(of: viewController, as: .image(on: .iPadPro12_9), named: "ipad-pro-12-9")

          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPhoneSe), named: "iphone-se")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPhone8), named: "iphone-8")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPhone8Plus), named: "iphone-8-plus")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPhoneX), named: "iphone-x")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPhoneXr), named: "iphone-xr")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPhoneXsMax), named: "iphone-xs-max")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPadMini), named: "ipad-mini")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPad9_7), named: "ipad-9-7")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPad10_2), named: "ipad-10-2")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPadPro10_5), named: "ipad-pro-10-5")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPadPro11), named: "ipad-pro-11")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .iPadPro12_9), named: "ipad-pro-12-9")

          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneSe(.portrait)), named: "iphone-se")
          assertSnapshot(of: viewController, as: .image(on: .iPhone8(.portrait)), named: "iphone-8")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhone8Plus(.portrait)), named: "iphone-8-plus")
          assertSnapshot(of: viewController, as: .image(on: .iPhoneX(.portrait)), named: "iphone-x")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneXr(.portrait)), named: "iphone-xr")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneXsMax(.portrait)), named: "iphone-xs-max")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadMini(.landscape)), named: "ipad-mini")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad9_7(.landscape)), named: "ipad-9-7")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad10_2(.landscape)), named: "ipad-10-2")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro10_5(.landscape)), named: "ipad-pro-10-5")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro11(.landscape)), named: "ipad-pro-11")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro12_9(.landscape)), named: "ipad-pro-12-9")

          assertSnapshot(
            of: viewController, as: .image(on: .iPadMini(.landscape(splitView: .oneThird))),
            named: "ipad-mini-33-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadMini(.landscape(splitView: .oneHalf))),
            named: "ipad-mini-50-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadMini(.landscape(splitView: .twoThirds))),
            named: "ipad-mini-66-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadMini(.portrait(splitView: .oneThird))),
            named: "ipad-mini-33-split-portrait")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadMini(.portrait(splitView: .twoThirds))),
            named: "ipad-mini-66-split-portrait")

          assertSnapshot(
            of: viewController, as: .image(on: .iPad9_7(.landscape(splitView: .oneThird))),
            named: "ipad-9-7-33-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad9_7(.landscape(splitView: .oneHalf))),
            named: "ipad-9-7-50-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad9_7(.landscape(splitView: .twoThirds))),
            named: "ipad-9-7-66-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad9_7(.portrait(splitView: .oneThird))),
            named: "ipad-9-7-33-split-portrait")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad9_7(.portrait(splitView: .twoThirds))),
            named: "ipad-9-7-66-split-portrait")

          assertSnapshot(
            of: viewController, as: .image(on: .iPad10_2(.landscape(splitView: .oneThird))),
            named: "ipad-10-2-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad10_2(.landscape(splitView: .oneHalf))),
            named: "ipad-10-2-50-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad10_2(.landscape(splitView: .twoThirds))),
            named: "ipad-10-2-66-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad10_2(.portrait(splitView: .oneThird))),
            named: "ipad-10-2-33-split-portrait")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad10_2(.portrait(splitView: .twoThirds))),
            named: "ipad-10-2-66-split-portrait")

          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro10_5(.landscape(splitView: .oneThird))),
            named: "ipad-pro-10inch-33-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro10_5(.landscape(splitView: .oneHalf))),
            named: "ipad-pro-10inch-50-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro10_5(.landscape(splitView: .twoThirds))),
            named: "ipad-pro-10inch-66-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro10_5(.portrait(splitView: .oneThird))),
            named: "ipad-pro-10inch-33-split-portrait")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro10_5(.portrait(splitView: .twoThirds))),
            named: "ipad-pro-10inch-66-split-portrait")

          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro11(.landscape(splitView: .oneThird))),
            named: "ipad-pro-11inch-33-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro11(.landscape(splitView: .oneHalf))),
            named: "ipad-pro-11inch-50-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro11(.landscape(splitView: .twoThirds))),
            named: "ipad-pro-11inch-66-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro11(.portrait(splitView: .oneThird))),
            named: "ipad-pro-11inch-33-split-portrait")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro11(.portrait(splitView: .twoThirds))),
            named: "ipad-pro-11inch-66-split-portrait")

          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro12_9(.landscape(splitView: .oneThird))),
            named: "ipad-pro-12inch-33-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro12_9(.landscape(splitView: .oneHalf))),
            named: "ipad-pro-12inch-50-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro12_9(.landscape(splitView: .twoThirds))),
            named: "ipad-pro-12inch-66-split-landscape")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro12_9(.portrait(splitView: .oneThird))),
            named: "ipad-pro-12inch-33-split-portrait")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro12_9(.portrait(splitView: .twoThirds))),
            named: "ipad-pro-12inch-66-split-portrait")

          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneSe(.landscape)),
            named: "iphone-se-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhone8(.landscape)), named: "iphone-8-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhone8Plus(.landscape)),
            named: "iphone-8-plus-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneX(.landscape)), named: "iphone-x-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneXr(.landscape)),
            named: "iphone-xr-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneXsMax(.landscape)),
            named: "iphone-xs-max-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadMini(.portrait)), named: "ipad-mini-alternative"
          )
          assertSnapshot(
            of: viewController, as: .image(on: .iPad9_7(.portrait)), named: "ipad-9-7-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad10_2(.portrait)), named: "ipad-10-2-alternative"
          )
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro10_5(.portrait)),
            named: "ipad-pro-10-5-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro11(.portrait)),
            named: "ipad-pro-11-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro12_9(.portrait)),
            named: "ipad-pro-12-9-alternative")

          allContentSizes.forEach { name, contentSize in
            assertSnapshot(
              of: viewController,
              as: .image(on: .iPhoneSe, traits: .init(preferredContentSizeCategory: contentSize)),
              named: "iphone-se-\(name)"
            )
          }
        #elseif os(tvOS)
          assertSnapshot(
            of: viewController, as: .image(on: .tv), named: "tv")
          assertSnapshot(
            of: viewController, as: .image(on: .tv4K), named: "tv4k")
        #elseif os(visionOS)
          // visionOS has no fixed device screens or orientations, so exercise the default
          // window preset plus one narrow geometry instead of the iPhone/iPad matrix.
          //
          // Note on size classes: measured empirically on the visionOS 2.5 simulator, the
          // offscreen snapshot window resolves horizontal and vertical size classes as
          // `.unspecified` at every window width (320-1920 pt) — unlike iOS device presets,
          // whose size classes come from explicit config traits, the visionOS window config
          // sets none and the offscreen window derives none from its geometry. A narrow
          // window therefore exercises layout at a different aspect ratio, not a size-class
          // change.
          assertSnapshot(
            of: viewController,
            as: .image(on: .visionOSWindow, traits: visionOSLightTraits),
            named: "visionos-window")
          assertSnapshot(
            of: viewController,
            as: .image(on: .visionOSWindow(width: 640, height: 720), traits: visionOSLightTraits),
            named: "visionos-window-640x720")
          assertSnapshot(
            of: viewController, as: .recursiveDescription(on: .visionOSWindow),
            named: "visionos-window")

          allContentSizes.forEach { name, contentSize in
            assertSnapshot(
              of: viewController,
              as: .image(
                on: .visionOSWindow,
                traits: .init(traitsFrom: [
                  visionOSLightTraits, .init(preferredContentSizeCategory: contentSize),
                ])),
              named: "visionos-window-\(name)"
            )
          }
        #endif
      }
    #endif
  }

  func testTraitsEmbeddedInTabNavigation() {
    #if os(iOS) || os(visionOS)
      if #available(iOS 11.0, *) {
        class MyViewController: UIViewController {
          let topLabel = UILabel()
          let leadingLabel = UILabel()
          let trailingLabel = UILabel()
          let bottomLabel = UILabel()

          override func viewDidLoad() {
            super.viewDidLoad()

            self.navigationItem.leftBarButtonItem = .init(
              barButtonSystemItem: .add, target: nil, action: nil)

            self.view.backgroundColor = .white

            self.topLabel.text = "What's"
            self.leadingLabel.text = "the"
            self.trailingLabel.text = "point"
            self.bottomLabel.text = "?"

            self.topLabel.translatesAutoresizingMaskIntoConstraints = false
            self.leadingLabel.translatesAutoresizingMaskIntoConstraints = false
            self.trailingLabel.translatesAutoresizingMaskIntoConstraints = false
            self.bottomLabel.translatesAutoresizingMaskIntoConstraints = false

            self.view.addSubview(self.topLabel)
            self.view.addSubview(self.leadingLabel)
            self.view.addSubview(self.trailingLabel)
            self.view.addSubview(self.bottomLabel)

            NSLayoutConstraint.activate([
              self.topLabel.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
              self.topLabel.centerXAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
              self.leadingLabel.leadingAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.leadingAnchor),
              self.leadingLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: self.view.safeAreaLayoutGuide.centerXAnchor),
              //            self.leadingLabel.trailingAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
              self.leadingLabel.centerYAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.centerYAnchor),
              self.trailingLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: self.view.safeAreaLayoutGuide.centerXAnchor),
              self.trailingLabel.trailingAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.trailingAnchor),
              self.trailingLabel.centerYAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.centerYAnchor),
              self.bottomLabel.bottomAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
              self.bottomLabel.centerXAnchor.constraint(
                equalTo: self.view.safeAreaLayoutGuide.centerXAnchor),
            ])
          }

          override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection)
            self.topLabel.font = .preferredFont(
              forTextStyle: .headline, compatibleWith: self.traitCollection)
            self.leadingLabel.font = .preferredFont(
              forTextStyle: .body, compatibleWith: self.traitCollection)
            self.trailingLabel.font = .preferredFont(
              forTextStyle: .body, compatibleWith: self.traitCollection)
            self.bottomLabel.font = .preferredFont(
              forTextStyle: .subheadline, compatibleWith: self.traitCollection)
            self.view.setNeedsUpdateConstraints()
            self.view.updateConstraintsIfNeeded()
          }
        }

        let myViewController = MyViewController()
        #if os(visionOS)
          // UITabBarController on visionOS resolves its content in dark appearance even when
          // a light-style trait override is applied anywhere in the hierarchy, which would
          // render the default label color white on this white background. Fix the label
          // color instead.
          for label in [
            myViewController.topLabel, myViewController.leadingLabel,
            myViewController.trailingLabel, myViewController.bottomLabel,
          ] {
            label.textColor = .black
          }
        #endif
        let navController = UINavigationController(rootViewController: myViewController)
        let viewController = UITabBarController()
        viewController.setViewControllers([navController], animated: false)

        #if os(visionOS)
          // visionOS has no fixed device screens or orientations, so snapshot the tab/nav
          // hierarchy in the single window preset instead of the iPhone/iPad matrix.
          assertSnapshot(
            of: viewController,
            as: .image(on: .visionOSWindow, traits: visionOSLightTraits),
            named: "visionos-window")
        #else
          assertSnapshot(of: viewController, as: .image(on: .iPhoneSe), named: "iphone-se")
          assertSnapshot(of: viewController, as: .image(on: .iPhone8), named: "iphone-8")
          assertSnapshot(of: viewController, as: .image(on: .iPhone8Plus), named: "iphone-8-plus")
          assertSnapshot(of: viewController, as: .image(on: .iPhoneX), named: "iphone-x")
          assertSnapshot(of: viewController, as: .image(on: .iPhoneXr), named: "iphone-xr")
          assertSnapshot(of: viewController, as: .image(on: .iPhoneXsMax), named: "iphone-xs-max")
          assertSnapshot(of: viewController, as: .image(on: .iPadMini), named: "ipad-mini")
          assertSnapshot(of: viewController, as: .image(on: .iPad9_7), named: "ipad-9-7")
          assertSnapshot(of: viewController, as: .image(on: .iPad10_2), named: "ipad-10-2")
          assertSnapshot(of: viewController, as: .image(on: .iPadPro10_5), named: "ipad-pro-10-5")
          assertSnapshot(of: viewController, as: .image(on: .iPadPro11), named: "ipad-pro-11")
          assertSnapshot(of: viewController, as: .image(on: .iPadPro12_9), named: "ipad-pro-12-9")

          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneSe(.portrait)), named: "iphone-se")
          assertSnapshot(of: viewController, as: .image(on: .iPhone8(.portrait)), named: "iphone-8")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhone8Plus(.portrait)), named: "iphone-8-plus")
          assertSnapshot(of: viewController, as: .image(on: .iPhoneX(.portrait)), named: "iphone-x")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneXr(.portrait)), named: "iphone-xr")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneXsMax(.portrait)), named: "iphone-xs-max")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadMini(.landscape)), named: "ipad-mini")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad9_7(.landscape)), named: "ipad-9-7")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad10_2(.landscape)), named: "ipad-10-2")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro10_5(.landscape)), named: "ipad-pro-10-5")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro11(.landscape)), named: "ipad-pro-11")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro12_9(.landscape)), named: "ipad-pro-12-9")

          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneSe(.landscape)),
            named: "iphone-se-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhone8(.landscape)), named: "iphone-8-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhone8Plus(.landscape)),
            named: "iphone-8-plus-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneX(.landscape)), named: "iphone-x-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneXr(.landscape)),
            named: "iphone-xr-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPhoneXsMax(.landscape)),
            named: "iphone-xs-max-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadMini(.portrait)), named: "ipad-mini-alternative"
          )
          assertSnapshot(
            of: viewController, as: .image(on: .iPad9_7(.portrait)), named: "ipad-9-7-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPad10_2(.portrait)), named: "ipad-10-2-alternative"
          )
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro10_5(.portrait)),
            named: "ipad-pro-10-5-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro11(.portrait)),
            named: "ipad-pro-11-alternative")
          assertSnapshot(
            of: viewController, as: .image(on: .iPadPro12_9(.portrait)),
            named: "ipad-pro-12-9-alternative")
        #endif
      }
    #endif
  }

  func testCollectionViewsWithMultipleScreenSizes() {
    #if os(iOS) || os(visionOS)

      final class CollectionViewController: UIViewController, UICollectionViewDataSource,
        UICollectionViewDelegateFlowLayout
      {

        let flowLayout: UICollectionViewFlowLayout = {
          let layout = UICollectionViewFlowLayout()
          layout.scrollDirection = .horizontal
          layout.minimumLineSpacing = 20
          return layout
        }()

        lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)

        override func viewDidLoad() {
          super.viewDidLoad()

          view.backgroundColor = .white
          view.addSubview(collectionView)

          collectionView.backgroundColor = .white
          collectionView.dataSource = self
          collectionView.delegate = self
          collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "Cell")
          collectionView.translatesAutoresizingMaskIntoConstraints = false

          NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            collectionView.trailingAnchor.constraint(
              equalTo: view.layoutMarginsGuide.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
          ])

          collectionView.reloadData()
        }

        override func viewDidLayoutSubviews() {
          super.viewDidLayoutSubviews()
          collectionView.collectionViewLayout.invalidateLayout()
        }

        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
          super.traitCollectionDidChange(previousTraitCollection)
          collectionView.collectionViewLayout.invalidateLayout()
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
          -> UICollectionViewCell
        {
          let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath)
          cell.contentView.backgroundColor = .orange
          return cell
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int)
          -> Int
        {
          return 20
        }

        func collectionView(
          _ collectionView: UICollectionView,
          layout collectionViewLayout: UICollectionViewLayout,
          sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
          return CGSize(
            width: min(collectionView.frame.width - 50, 300),
            height: collectionView.frame.height
          )
        }

      }

      let viewController = CollectionViewController()

      #if os(visionOS)
        // visionOS has freely resizable windows rather than multiple device screen sizes, so
        // the size-dependent collection layout is exercised across representative window
        // geometries: narrow (half the default width), the HIG default (1280x720 pt), and a
        // large 16:9 window.
        assertSnapshots(
          of: viewController,
          as: [
            "visionos-window-640x720": .image(
              on: .visionOSWindow(width: 640, height: 720), traits: visionOSLightTraits),
            "visionos-window-1280x720": .image(on: .visionOSWindow, traits: visionOSLightTraits),
            "visionos-window-1920x1080": .image(
              on: .visionOSWindow(width: 1920, height: 1080), traits: visionOSLightTraits),
          ])
      #else
        assertSnapshots(
          of: viewController,
          as: [
            "ipad": .image(on: .iPadPro12_9),
            "iphoneSe": .image(on: .iPhoneSe),
            "iphone8": .image(on: .iPhone8),
            "iphoneMax": .image(on: .iPhoneXsMax),
          ])
      #endif
    #endif
  }

  func testTraitsWithView() {
    #if os(iOS) || os(visionOS)
      if #available(iOS 11.0, *) {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .title1)
        label.adjustsFontForContentSizeCategory = true
        label.text = "What's the point?"

        allContentSizes.forEach { name, contentSize in
          #if os(visionOS)
            let fixtureName = "label-\(name)-visionos"
            let traits = UITraitCollection(traitsFrom: [
              .init(preferredContentSizeCategory: contentSize),
              visionOSLightTraits,
            ])
          #else
            let fixtureName = "label-\(name)"
            let traits = UITraitCollection(preferredContentSizeCategory: contentSize)
          #endif
          assertSnapshot(
            of: label,
            as: .image(traits: traits),
            named: fixtureName
          )
        }
      }
    #endif
  }

  func testTraitsWithViewController() {
    #if os(iOS) || os(visionOS)
      let label = UILabel()
      label.font = .preferredFont(forTextStyle: .title1)
      label.adjustsFontForContentSizeCategory = true
      label.text = "What's the point?"

      let viewController = UIViewController()
      viewController.view.addSubview(label)

      label.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(
          equalTo: viewController.view.layoutMarginsGuide.leadingAnchor),
        label.topAnchor.constraint(equalTo: viewController.view.layoutMarginsGuide.topAnchor),
        label.trailingAnchor.constraint(
          equalTo: viewController.view.layoutMarginsGuide.trailingAnchor),
      ])

      allContentSizes.forEach { name, contentSize in
        #if os(visionOS)
          assertSnapshot(
            of: viewController,
            as: .recursiveDescription(
              on: .visionOSWindow, traits: .init(preferredContentSizeCategory: contentSize)),
            named: "label-\(name)-visionos"
          )
        #else
          assertSnapshot(
            of: viewController,
            as: .recursiveDescription(
              on: .iPhoneSe, traits: .init(preferredContentSizeCategory: contentSize)),
            named: "label-\(name)"
          )
        #endif
      }
    #endif
  }

  func testUIBezierPath() {
    #if os(iOS) || os(tvOS) || os(visionOS)
      let path = UIBezierPath.heart

      let osName: String
      #if os(iOS)
        osName = "iOS"
      #elseif os(tvOS)
        osName = "tvOS"
      #elseif os(visionOS)
        osName = "visionOS"
      #endif

      if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
        assertSnapshot(of: path, as: .image, named: osName)
      }

      if #available(iOS 11.0, tvOS 11.0, *) {
        assertSnapshot(of: path, as: .elementsDescription, named: osName)
      }
    #endif
  }

  func testUIView() {
    #if os(iOS) || os(visionOS)
      let view = UIButton(type: .contactAdd)
      assertSnapshot(of: view, as: .image, named: visionOSSuffix)
      assertSnapshot(of: view, as: .recursiveDescription, named: visionOSSuffix)
    #endif
  }

  func testUIViewControllerLifeCycle() {
    #if os(iOS) || os(visionOS)
      class ViewController: UIViewController {
        let viewDidLoadExpectation: XCTestExpectation
        let viewWillAppearExpectation: XCTestExpectation
        let viewDidAppearExpectation: XCTestExpectation
        let viewWillDisappearExpectation: XCTestExpectation
        let viewDidDisappearExpectation: XCTestExpectation
        init(
          viewDidLoadExpectation: XCTestExpectation,
          viewWillAppearExpectation: XCTestExpectation,
          viewDidAppearExpectation: XCTestExpectation,
          viewWillDisappearExpectation: XCTestExpectation,
          viewDidDisappearExpectation: XCTestExpectation
        ) {
          self.viewDidLoadExpectation = viewDidLoadExpectation
          self.viewWillAppearExpectation = viewWillAppearExpectation
          self.viewDidAppearExpectation = viewDidAppearExpectation
          self.viewWillDisappearExpectation = viewWillDisappearExpectation
          self.viewDidDisappearExpectation = viewDidDisappearExpectation
          super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) {
          fatalError("init(coder:) has not been implemented")
        }
        override func viewDidLoad() {
          super.viewDidLoad()
          viewDidLoadExpectation.fulfill()
        }
        override func viewWillAppear(_ animated: Bool) {
          super.viewWillAppear(animated)
          viewWillAppearExpectation.fulfill()
        }
        override func viewDidAppear(_ animated: Bool) {
          super.viewDidAppear(animated)
          viewDidAppearExpectation.fulfill()
        }
        override func viewWillDisappear(_ animated: Bool) {
          super.viewWillDisappear(animated)
          viewWillDisappearExpectation.fulfill()
        }
        override func viewDidDisappear(_ animated: Bool) {
          super.viewDidDisappear(animated)
          viewDidDisappearExpectation.fulfill()
        }
      }

      let viewDidLoadExpectation = expectation(description: "viewDidLoad")
      let viewWillAppearExpectation = expectation(description: "viewWillAppear")
      let viewDidAppearExpectation = expectation(description: "viewDidAppear")
      let viewWillDisappearExpectation = expectation(description: "viewWillDisappear")
      let viewDidDisappearExpectation = expectation(description: "viewDidDisappear")
      viewWillAppearExpectation.expectedFulfillmentCount = 4
      viewDidAppearExpectation.expectedFulfillmentCount = 4
      #if os(visionOS)
        // The visionOS window teardown after each snapshot delivers viewWillDisappear once per
        // snapshot (instead of twice on iOS) and never completes the disappearance transition.
        viewWillDisappearExpectation.expectedFulfillmentCount = 2
        // The visionOS simulator does not deliver viewDidDisappear during window teardown, so the
        // expectation is inverted rather than dropped from the wait below.
        viewDidDisappearExpectation.isInverted = true
      #else
        viewWillDisappearExpectation.expectedFulfillmentCount = 4
        viewDidDisappearExpectation.expectedFulfillmentCount = 4
      #endif

      let viewController = ViewController(
        viewDidLoadExpectation: viewDidLoadExpectation,
        viewWillAppearExpectation: viewWillAppearExpectation,
        viewDidAppearExpectation: viewDidAppearExpectation,
        viewWillDisappearExpectation: viewWillDisappearExpectation,
        viewDidDisappearExpectation: viewDidDisappearExpectation
      )

      #if os(visionOS)
        assertSnapshot(of: viewController, as: .image, named: "visionos-1")
        assertSnapshot(of: viewController, as: .image, named: "visionos-2")
      #else
        assertSnapshot(of: viewController, as: .image)
        assertSnapshot(of: viewController, as: .image)
      #endif

      wait(
        for: [
          viewDidLoadExpectation,
          viewWillAppearExpectation,
          viewDidAppearExpectation,
          viewWillDisappearExpectation,
          viewDidDisappearExpectation,
        ], timeout: 1.0, enforceOrder: true)
    #endif
  }

  func testCALayer() {
    #if os(iOS) || os(visionOS) || os(macOS)
      let layer = CALayer()
      layer.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
      layer.borderWidth = 4.0
      #if os(macOS)
        layer.backgroundColor = NSColor.red.cgColor
        layer.borderColor = NSColor.black.cgColor
        if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
          assertSnapshot(of: layer, as: .image(precision: 1, scale: 2), named: "macos")
        }
      #else
        layer.backgroundColor = UIColor.red.cgColor
        layer.borderColor = UIColor.black.cgColor
        assertSnapshot(of: layer, as: .image, named: visionOSSuffix)
      #endif
    #endif
  }

  func testCALayerWithGradient() {
    #if os(iOS) || os(visionOS) || os(macOS)
      let baseLayer = CALayer()
      baseLayer.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
      let gradientLayer = CAGradientLayer()
      #if os(macOS)
        gradientLayer.colors = [NSColor.red.cgColor, NSColor.yellow.cgColor]
      #else
        gradientLayer.colors = [UIColor.red.cgColor, UIColor.yellow.cgColor]
      #endif
      gradientLayer.frame = baseLayer.frame
      baseLayer.addSublayer(gradientLayer)
      #if os(macOS)
        if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
          assertSnapshot(of: baseLayer, as: .image(precision: 1, scale: 2), named: "macos")
        }
      #else
        assertSnapshot(of: baseLayer, as: .image, named: visionOSSuffix)
      #endif
    #endif
  }

  func testViewControllerHierarchy() {
    #if os(iOS) || os(visionOS)
      let page = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
      page.setViewControllers([UIViewController()], direction: .forward, animated: false)
      let tab = UITabBarController()
      tab.viewControllers = [
        UINavigationController(rootViewController: page),
        UINavigationController(rootViewController: UIViewController()),
        UINavigationController(rootViewController: UIViewController()),
        UINavigationController(rootViewController: UIViewController()),
        UINavigationController(rootViewController: UIViewController()),
      ]
      assertSnapshot(of: tab, as: .hierarchy, named: visionOSSuffix)
    #endif
  }

  func testURLRequest() {
    var get = URLRequest(url: URL(string: "https://www.pointfree.co/")!)
    get.addValue("pf_session={}", forHTTPHeaderField: "Cookie")
    get.addValue("text/html", forHTTPHeaderField: "Accept")
    get.addValue("application/json", forHTTPHeaderField: "Content-Type")
    assertSnapshot(of: get, as: .raw, named: "get")
    assertSnapshot(of: get, as: .curl, named: "get-curl")

    var getWithQuery = URLRequest(
      url: URL(string: "https://www.pointfree.co?key_2=value_2&key_1=value_1&key_3=value_3")!)
    getWithQuery.addValue("pf_session={}", forHTTPHeaderField: "Cookie")
    getWithQuery.addValue("text/html", forHTTPHeaderField: "Accept")
    getWithQuery.addValue("application/json", forHTTPHeaderField: "Content-Type")
    assertSnapshot(of: getWithQuery, as: .raw, named: "get-with-query")
    assertSnapshot(of: getWithQuery, as: .curl, named: "get-with-query-curl")

    var post = URLRequest(url: URL(string: "https://www.pointfree.co/subscribe")!)
    post.httpMethod = "POST"
    post.addValue("pf_session={\"user_id\":\"0\"}", forHTTPHeaderField: "Cookie")
    post.addValue("text/html", forHTTPHeaderField: "Accept")
    post.httpBody = Data("pricing[billing]=monthly&pricing[lane]=individual".utf8)
    assertSnapshot(of: post, as: .raw, named: "post")
    assertSnapshot(of: post, as: .curl, named: "post-curl")

    var postWithJSON = URLRequest(
      url: URL(string: "http://dummy.restapiexample.com/api/v1/create")!)
    postWithJSON.httpMethod = "POST"
    postWithJSON.addValue("application/json", forHTTPHeaderField: "Content-Type")
    postWithJSON.addValue("application/json", forHTTPHeaderField: "Accept")
    postWithJSON.httpBody = Data(
      "{\"name\":\"tammy134235345235\", \"salary\":0, \"age\":\"tammy133\"}".utf8)
    assertSnapshot(of: postWithJSON, as: .raw, named: "post-with-json")
    assertSnapshot(of: postWithJSON, as: .curl, named: "post-with-json-curl")

    var head = URLRequest(url: URL(string: "https://www.pointfree.co/")!)
    head.httpMethod = "HEAD"
    head.addValue("pf_session={}", forHTTPHeaderField: "Cookie")
    assertSnapshot(of: head, as: .raw, named: "head")
    assertSnapshot(of: head, as: .curl, named: "head-curl")

    post = URLRequest(url: URL(string: "https://www.pointfree.co/subscribe")!)
    post.httpMethod = "POST"
    post.addValue("pf_session={\"user_id\":\"0\"}", forHTTPHeaderField: "Cookie")
    post.addValue("application/json", forHTTPHeaderField: "Accept")
    post.httpBody = Data(
      """
      {"pricing": {"lane": "individual","billing": "monthly"}}
      """.utf8)
  }

  func testWebView() throws {
    #if os(iOS) || os(macOS) || os(visionOS)
      let fixtureUrl = URL(fileURLWithPath: String(#file), isDirectory: false)
        .deletingLastPathComponent()
        .appendingPathComponent("__Fixtures__/pointfree.html")
      let html = try String(contentsOf: fixtureUrl)
      let webView = WKWebView()
      webView.loadHTMLString(html, baseURL: nil)
      if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
        assertSnapshot(
          of: webView,
          as: .image(
            perceptualPrecision: webViewPerceptualPrecision, size: .init(width: 800, height: 600)),
          named: platform,
          timeout: webViewTimeout
        )
      }
    #endif
  }

  func testViewWithZeroHeightOrWidth() {
    #if os(iOS) || os(tvOS) || os(visionOS)
      var rect = CGRect(x: 0, y: 0, width: 350, height: 0)
      var view = UIView(frame: rect)
      view.backgroundColor = .red
      assertSnapshot(of: view, as: .image, named: "noHeight")

      rect = CGRect(x: 0, y: 0, width: 0, height: 350)
      view = UIView(frame: rect)
      view.backgroundColor = .green
      assertSnapshot(of: view, as: .image, named: "noWidth")

      rect = CGRect(x: 0, y: 0, width: 0, height: 0)
      view = UIView(frame: rect)
      view.backgroundColor = .blue
      assertSnapshot(of: view, as: .image, named: "noWidth.noHeight")
    #endif
  }

  func testViewAgainstEmptyImage() {
    #if os(iOS) || os(tvOS) || os(visionOS)
      let rect = CGRect(x: 0, y: 0, width: 0, height: 0)
      let view = UIView(frame: rect)
      view.backgroundColor = .blue

      // NB: The comparison is expected to fail, so re-recording must stay off or the suite's
      //     'record: .failed' mode overwrites the reference with the zero-size placeholder.
      let failure = verifySnapshot(of: view, as: .image, named: "notEmptyImage", record: .never)
      XCTAssertNotNil(failure)
    #endif
  }

  func testEmbeddedWebView() throws {
    #if os(iOS) || os(visionOS)
      let label = UILabel()
      label.text = "Hello, Blob!"

      let fixtureUrl = URL(fileURLWithPath: String(#file), isDirectory: false)
        .deletingLastPathComponent()
        .appendingPathComponent("__Fixtures__/pointfree.html")
      let html = try String(contentsOf: fixtureUrl)
      let webView = WKWebView()
      webView.loadHTMLString(html, baseURL: nil)
      webView.isHidden = true

      let stackView = UIStackView(arrangedSubviews: [label, webView])
      stackView.axis = .vertical

      if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
        #if os(visionOS)
          let traits: UITraitCollection = visionOSLightTraits
        #else
          let traits = UITraitCollection()
        #endif
        assertSnapshot(
          of: stackView,
          as: .image(
            perceptualPrecision: webViewPerceptualPrecision, size: .init(width: 800, height: 600),
            traits: traits),
          named: platform,
          timeout: webViewTimeout
        )
      }
    #endif
  }

  #if os(iOS) || os(macOS) || os(visionOS)
    final class ManipulatingWKWebViewNavigationDelegate: NSObject, WKNavigationDelegate {
      func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.body.children[0].classList.remove(\"hero\")")  // Change layout
      }
    }
    func testWebViewWithManipulatingNavigationDelegate() throws {
      let manipulatingWKWebViewNavigationDelegate = ManipulatingWKWebViewNavigationDelegate()
      let webView = WKWebView()
      webView.navigationDelegate = manipulatingWKWebViewNavigationDelegate

      let fixtureUrl = URL(fileURLWithPath: String(#file), isDirectory: false)
        .deletingLastPathComponent()
        .appendingPathComponent("__Fixtures__/pointfree.html")
      let html = try String(contentsOf: fixtureUrl)
      webView.loadHTMLString(html, baseURL: nil)
      if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
        assertSnapshot(
          of: webView,
          as: .image(
            perceptualPrecision: webViewPerceptualPrecision, size: .init(width: 800, height: 600)),
          named: platform,
          timeout: webViewTimeout
        )
      }
      _ = manipulatingWKWebViewNavigationDelegate
    }

    final class CancellingWKWebViewNavigationDelegate: NSObject, WKNavigationDelegate {
      func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
      ) {
        decisionHandler(.cancel)
      }
    }

    func testWebViewWithCancellingNavigationDelegate() throws {
      let cancellingWKWebViewNavigationDelegate = CancellingWKWebViewNavigationDelegate()
      let webView = WKWebView()
      webView.navigationDelegate = cancellingWKWebViewNavigationDelegate

      let fixtureUrl = URL(fileURLWithPath: String(#file), isDirectory: false)
        .deletingLastPathComponent()
        .appendingPathComponent("__Fixtures__/pointfree.html")
      let html = try String(contentsOf: fixtureUrl)
      webView.loadHTMLString(html, baseURL: nil)
      if !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW") {
        assertSnapshot(
          of: webView,
          as: .image(
            perceptualPrecision: webViewPerceptualPrecision, size: .init(width: 800, height: 600)),
          named: platform,
          timeout: webViewTimeout
        )
      }
      _ = cancellingWKWebViewNavigationDelegate
    }
  #endif

  #if os(iOS)
    @available(iOS 13.0, *)
    func testSwiftUIView_iOS() {
      struct MyView: SwiftUI.View {
        var body: some SwiftUI.View {
          HStack {
            Image(systemName: "checkmark.circle.fill")
            Text("Checked").fixedSize()
          }
          .padding(5)
          .background(RoundedRectangle(cornerRadius: 5.0).fill(Color.blue))
          .padding(10)
        }
      }

      let view = MyView().background(Color.yellow)

      assertSnapshot(of: view, as: .image(traits: .init(userInterfaceStyle: .light)))
      assertSnapshot(
        of: view, as: .image(layout: .sizeThatFits, traits: .init(userInterfaceStyle: .light)),
        named: "size-that-fits")
      assertSnapshot(
        of: view,
        as: .image(
          layout: .fixed(width: 200.0, height: 100.0), traits: .init(userInterfaceStyle: .light)),
        named: "fixed")
      assertSnapshot(
        of: view,
        as: .image(layout: .device(config: .iPhoneSe), traits: .init(userInterfaceStyle: .light)),
        named: "device")
    }
  #endif

  #if os(tvOS)
    @available(tvOS 13.0, *)
    func testSwiftUIView_tvOS() {
      struct MyView: SwiftUI.View {
        var body: some SwiftUI.View {
          HStack {
            Image(systemName: "checkmark.circle.fill")
            Text("Checked").fixedSize()
          }
          .padding(5)
          .background(RoundedRectangle(cornerRadius: 5.0).fill(Color.blue))
          .padding(10)
        }
      }
      let view = MyView().background(Color.yellow)

      assertSnapshot(of: view, as: .image())
      assertSnapshot(of: view, as: .image(layout: .sizeThatFits), named: "size-that-fits")
      assertSnapshot(
        of: view, as: .image(layout: .fixed(width: 300.0, height: 100.0)), named: "fixed")
      assertSnapshot(of: view, as: .image(layout: .device(config: .tv)), named: "device")
    }
  #endif

  #if os(visionOS)
    func testWebViewThatNeverPaints_visionOS() {
      // Overriding `requestAnimationFrame` with a no-op is the deterministic stand-in for a page
      // that finishes loading and never paints, which is what the deadline exists to catch.
      let html = """
        <script>window.requestAnimationFrame = () => {}</script>
        """
      let webView = WKWebView(frame: .init(x: 0, y: 0, width: 100, height: 100))
      webView.loadHTMLString(html, baseURL: nil)

      let deadline = webContentFrameDeadline
      webContentFrameDeadline = 2
      defer { webContentFrameDeadline = deadline }

      let started = Date()
      // NB: The comparison must never run, so re-recording stays off; the suite's
      //     'record: .failed' mode would otherwise write a blank reference.
      let failure = verifySnapshot(
        of: webView,
        as: .image(size: .init(width: 100, height: 100)),
        named: "neverPaints",
        record: .never,
        timeout: webViewTimeout
      )

      XCTAssertEqual(
        failure?.contains("never produced a frame"), true,
        "Expected the painted-frame diagnosis, got: \(failure ?? "no failure")")
      XCTAssertLessThan(Date().timeIntervalSince(started), webViewTimeout)
    }

    func testWebViewSnapshotWaitsForLoading_visionOS() throws {
      // Snapshotting a web view that is still loading must produce the settled page: the
      // `isLoading` observer, not an early render of a blank content process.
      let html = """
        <body style="margin:0;background:#ff0000"></body>
        """
      let size = CGSize(width: 100, height: 100)
      let webView = WKWebView(frame: .init(origin: .zero, size: size))
      webView.loadHTMLString(html, baseURL: nil)
      XCTAssertTrue(webView.isLoading, "The observer path is only exercised while loading")

      let tookSnapshot = XCTestExpectation(description: "Took snapshot")
      var image: UIImage?
      Snapshotting<UIView, UIImage>.image(size: size).snapshot(webView).run {
        image = $0
        tookSnapshot.fulfill()
      }
      XCTAssertEqual(XCTWaiter.wait(for: [tookSnapshot], timeout: webViewTimeout), .completed)

      let center = try XCTUnwrap(XCTUnwrap(image).centerPixel())
      XCTAssertEqual(center.red, 255)
      XCTAssertLessThan(center.green, 8)
      XCTAssertLessThan(center.blue, 8)
      XCTAssertEqual(center.alpha, 255)
    }

    func testSwiftUIView_visionOS() {
      // swiftUIProbe and a fixed background, not SF Symbol + Text + Color.yellow: OS-drawn
      // pixels are only stable while the simulator runtime pin holds, shapes in explicit colors
      // are stable by construction (see TestHelpers.swift).
      let view = swiftUIProbe.background(Color(red: 1.0, green: 0.8, blue: 0.0))

      assertSnapshot(of: view, as: .image())
      assertSnapshot(of: view, as: .image(layout: .sizeThatFits), named: "size-that-fits")
      assertSnapshot(
        of: view, as: .image(layout: .fixed(width: 300.0, height: 100.0)), named: "fixed")
      assertSnapshot(
        of: view,
        as: .image(layout: .device(config: .visionOSWindow), traits: visionOSLightTraits),
        named: "device")
    }
  #endif

  #if os(macOS)
    func testSwiftUIView_macOS() {
      // Fixed color, not Color.yellow: semantic colors are retuned across OS releases (macOS 26.5
      // draws yellow as (255,204,0), 26.6 as (255,214,1)), which busts the reference beyond even
      // perceptual tolerance while the library's own behavior is unchanged.
      let view = swiftUIProbe.background(Color(red: 1.0, green: 0.8, blue: 0.0))

      assertSnapshot(of: view, as: .image(perceptualPrecision: 0.98, scale: 2))
      assertSnapshot(
        of: view, as: .image(perceptualPrecision: 0.98, layout: .sizeThatFits, scale: 2),
        named: "size-that-fits")
      assertSnapshot(
        of: view,
        as: .image(
          perceptualPrecision: 0.98, layout: .fixed(width: 300.0, height: 100.0), scale: 2),
        named: "fixed")

      // System colors resolve against the effective appearance, so the two renders must differ.
      if #available(macOS 12.0, *) {
        let appearanceView = swiftUIProbe.background(Color(nsColor: .windowBackgroundColor))
        assertSnapshot(
          of: appearanceView,
          as: .image(perceptualPrecision: 0.98, appearance: NSAppearance(named: .aqua), scale: 2),
          named: "light")
        assertSnapshot(
          of: appearanceView,
          as: .image(
            perceptualPrecision: 0.98, appearance: NSAppearance(named: .darkAqua), scale: 2),
          named: "dark")
      }
    }
  #endif
}

#if os(iOS) || os(visionOS)
  private let allContentSizes =
    [
      "extra-small": UIContentSizeCategory.extraSmall,
      "small": .small,
      "medium": .medium,
      "large": .large,
      "extra-large": .extraLarge,
      "extra-extra-large": .extraExtraLarge,
      "extra-extra-extra-large": .extraExtraExtraLarge,
      "accessibility-medium": .accessibilityMedium,
      "accessibility-large": .accessibilityLarge,
      "accessibility-extra-large": .accessibilityExtraLarge,
      "accessibility-extra-extra-large": .accessibilityExtraExtraLarge,
      "accessibility-extra-extra-extra-large": .accessibilityExtraExtraExtraLarge,
    ]
#endif
