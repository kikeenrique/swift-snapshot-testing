#if compiler(>=6) && canImport(Testing)
  import Testing
  import SnapshotTesting

  #if canImport(AppKit)
    import AppKit
  #endif

  #if canImport(UIKit)
    import UIKit
  #endif

  extension BaseSuite {
    @Suite(.serialized, .snapshots(record: .missing))
    struct SwiftTestingTests {
      @Test func testSnapshot() {
        assertSnapshot(of: ["Hello", "World"], as: .dump, named: "snap")
        withKnownIssue {
          assertSnapshot(of: ["Goodbye", "World"], as: .dump, named: "snap")
        } matching: { issue in
          issue.description.hasSuffix(
            """
            @@ −1,4 +1,4 @@
             ▿ 2 elements
            −  - "Hello"
            +  - "Goodbye"
               - "World"
            """
          )
        }
      }

      #if canImport(UIKit)
        @Test(
          .enabled {
            !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW")
          }
        )
        func testUIImage() {
          let redPixel = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image {
            context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
          }
          let bluePixel = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image {
            context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
          }
          assertSnapshot(of: redPixel, as: .image, named: "pixel")
          withKnownIssue {
            assertSnapshot(of: bluePixel, as: .image, named: "pixel")
          } matching: { issue in
            issue.description.hasSuffix(
              "Newly-taken snapshot does not match reference."
            )
          }
        }
      #endif

      #if canImport(AppKit)
        @Test(
          .enabled {
            !ProcessInfo.processInfo.environment.keys.contains("GITHUB_WORKFLOW")
          }
        )
        func testNSImage() {
          // An explicit 1×1 bitmap rep, not NSImage(size:flipped:): a drawing-handler image
          // rasterizes at the host display's backing scale, so a Retina machine records a 2×2 px
          // reference that a 1x machine can never reproduce.
          func pixel(_ color: NSColor) -> NSImage {
            let rep = NSBitmapImageRep(
              bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
              samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
              bytesPerRow: 4, bitsPerPixel: 32)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            color.setFill()
            NSRect(x: 0, y: 0, width: 1, height: 1).fill()
            NSGraphicsContext.restoreGraphicsState()
            let image = NSImage(size: NSSize(width: 1, height: 1))
            image.addRepresentation(rep)
            return image
          }
          let redPixel = pixel(.red)
          let bluePixel = pixel(.blue)
          assertSnapshot(of: redPixel, as: .image, named: "pixel")
          withKnownIssue {
            assertSnapshot(of: bluePixel, as: .image, named: "pixel")
          } matching: { issue in
            issue.description.hasSuffix(
              "Newly-taken snapshot does not match reference."
            )
          }
        }
      #endif

    }
  }
#endif
