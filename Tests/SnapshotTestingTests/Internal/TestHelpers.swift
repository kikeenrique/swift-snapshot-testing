import XCTest

@testable import SnapshotTesting

/// Snapshot name suffix for assertions whose only platform difference is that visionOS records
/// its own fixture. `nil` is the default of `assertSnapshot(named:)`, so on every other platform
/// this produces the exact same fixture name as omitting the argument.
#if os(visionOS)
  let visionOSSuffix: String? = "visionos"
#else
  let visionOSSuffix: String? = nil
#endif

#if canImport(SwiftUI) && os(macOS)
  import SwiftUI

  /// Content for the macOS SwiftUI strategy tests, drawn entirely from shapes in explicit colors.
  ///
  /// These tests assert on the strategy — layout mode, size override, pinned scale, appearance —
  /// not on how the system draws. Text and SF Symbols are rasterized by the OS, so a reference
  /// containing them stops matching after an OS update even though nothing in the library changed;
  /// shapes and fixed colors keep the reference portable across machines and releases. Intrinsic
  /// sizes are explicit so `.sizeThatFits` still has something to measure.
  @available(macOS 11.0, *)
  var swiftUIProbe: some SwiftUI.View {
    HStack(spacing: 4) {
      Circle()
        .fill(Color(red: 0.2, green: 0.7, blue: 0.3))
        .frame(width: 16, height: 16)
      Rectangle()
        .fill(Color(white: 1.0))
        .frame(width: 48, height: 10)
    }
    .padding(5)
    .background(RoundedRectangle(cornerRadius: 5.0).fill(Color(red: 0.1, green: 0.3, blue: 0.9)))
    .padding(10)
  }
#endif

#if os(iOS)
  let platform = "ios"
#elseif os(tvOS)
  let platform = "tvos"
#elseif os(visionOS)
  let platform = "visionos"
#elseif os(macOS)
  let platform = "macos"
  extension NSTextField {
    var text: String {
      get { return self.stringValue }
      set { self.stringValue = newValue }
    }
  }
#endif

#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
  extension Snapshotting where Value == SnapshotTesting.View, Format == SnapshotTesting.Image {
    /// `.image`, with the light appearance pinned — one spelling on every platform.
    ///
    /// Both platforms' image strategies default to inheriting the appearance from the host, which
    /// makes the recording machine's system setting part of the reference: a reference recorded in
    /// Dark mode does not match one recorded in Light mode, and a control drawn with dynamic system
    /// colors can come out light-on-light with no visible content at all. Pinning is the fix, but it
    /// is spelled twice — AppKit takes `appearance: NSAppearance(named: .aqua)`, UIKit takes
    /// `traits: UITraitCollection(userInterfaceStyle: .light)` — so cross-platform tests need a
    /// `#if` fork purely to change the parameter's name.
    ///
    /// macOS additionally pins `scale: 2`. A pinned scale and a pinned appearance are the same
    /// portability concern (both keep the host machine out of the reference), and UIKit has no
    /// `scale:` parameter because the simulator's scale already comes from the trait collection —
    /// that asymmetry belongs here rather than at every call site.
    static func lightImage(
      precision: Float = 1, perceptualPrecision: Float = 1, size: CGSize? = nil
    ) -> Snapshotting {
      #if os(macOS)
        return .image(
          precision: precision, perceptualPrecision: perceptualPrecision, size: size,
          appearance: NSAppearance(named: .aqua), scale: 2)
      #else
        return .image(
          precision: precision, perceptualPrecision: perceptualPrecision, size: size,
          traits: .init(userInterfaceStyle: .light))
      #endif
    }
  }

  extension CGPath {
    /// Creates an approximation of a heart at a 45º angle with a circle above, using all available element types:
    static var heart: CGPath {
      let scale: CGFloat = 30.0
      let path = CGMutablePath()

      path.move(to: CGPoint(x: 0.0 * scale, y: 0.0 * scale))
      path.addLine(to: CGPoint(x: 0.0 * scale, y: 2.0 * scale))
      path.addQuadCurve(
        to: CGPoint(x: 1.0 * scale, y: 3.0 * scale),
        control: CGPoint(x: 0.125 * scale, y: 2.875 * scale)
      )
      path.addQuadCurve(
        to: CGPoint(x: 2.0 * scale, y: 2.0 * scale),
        control: CGPoint(x: 1.875 * scale, y: 2.875 * scale)
      )
      path.addCurve(
        to: CGPoint(x: 3.0 * scale, y: 1.0 * scale),
        control1: CGPoint(x: 2.5 * scale, y: 2.0 * scale),
        control2: CGPoint(x: 3.0 * scale, y: 1.5 * scale)
      )
      path.addCurve(
        to: CGPoint(x: 2.0 * scale, y: 0.0 * scale),
        control1: CGPoint(x: 3.0 * scale, y: 0.5 * scale),
        control2: CGPoint(x: 2.5 * scale, y: 0.0 * scale)
      )
      path.addLine(to: CGPoint(x: 0.0 * scale, y: 0.0 * scale))
      path.closeSubpath()

      path.addEllipse(
        in: CGRect(
          origin: CGPoint(x: 2.0 * scale, y: 2.0 * scale),
          size: CGSize(width: scale, height: scale)
        ))

      return path
    }
  }
#endif

#if os(iOS) || os(tvOS) || os(visionOS)
  extension UIBezierPath {
    /// Creates an approximation of a heart at a 45º angle with a circle above, using all available element types:
    static var heart: UIBezierPath {
      UIBezierPath(cgPath: .heart)
    }
  }
#endif

#if os(macOS)
  extension NSBezierPath {
    /// Creates an approximation of a heart at a 45º angle with a circle above, using all available element types:
    static var heart: NSBezierPath {
      let scale: CGFloat = 30.0
      let path = NSBezierPath()

      path.move(to: CGPoint(x: 0.0 * scale, y: 0.0 * scale))
      path.line(to: CGPoint(x: 0.0 * scale, y: 2.0 * scale))
      path.curve(
        to: CGPoint(x: 1.0 * scale, y: 3.0 * scale),
        controlPoint1: CGPoint(x: 0.0 * scale, y: 2.5 * scale),
        controlPoint2: CGPoint(x: 0.5 * scale, y: 3.0 * scale)
      )
      path.curve(
        to: CGPoint(x: 2.0 * scale, y: 2.0 * scale),
        controlPoint1: CGPoint(x: 1.5 * scale, y: 3.0 * scale),
        controlPoint2: CGPoint(x: 2.0 * scale, y: 2.5 * scale)
      )
      path.curve(
        to: CGPoint(x: 3.0 * scale, y: 1.0 * scale),
        controlPoint1: CGPoint(x: 2.5 * scale, y: 2.0 * scale),
        controlPoint2: CGPoint(x: 3.0 * scale, y: 1.5 * scale)
      )
      path.curve(
        to: CGPoint(x: 2.0 * scale, y: 0.0 * scale),
        controlPoint1: CGPoint(x: 3.0 * scale, y: 0.5 * scale),
        controlPoint2: CGPoint(x: 2.5 * scale, y: 0.0 * scale)
      )
      path.line(to: CGPoint(x: 0.0 * scale, y: 0.0 * scale))
      path.close()

      path.appendOval(
        in: CGRect(
          origin: CGPoint(x: 2.0 * scale, y: 2.0 * scale),
          size: CGSize(width: scale, height: scale)
        ))

      return path
    }
  }
#endif
