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

#if canImport(SwiftUI) && os(visionOS)
  import SwiftUI

  /// Content for the visionOS SwiftUI strategy test, drawn entirely from shapes in explicit
  /// colors.
  ///
  /// The test asserts on the strategy — layout mode, size override, window preset — not on how
  /// the system draws. Text, SF Symbols, and semantic colors like `Color.yellow` are rasterized
  /// by the OS, so a reference containing them survives only as long as the simulator runtime
  /// pin holds; shapes and fixed colors keep the reference portable across runtimes by
  /// construction. Intrinsic sizes are explicit so `.sizeThatFits` still has something to
  /// measure.
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
