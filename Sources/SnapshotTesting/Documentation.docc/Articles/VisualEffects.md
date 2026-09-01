# Snapshotting visual effects and system chrome

Learn why views that use Liquid Glass, blurs, and other system-composited effects require a host
application and `drawHierarchyInKeyWindow`, and how to configure your test target for them.

## Overview

Image strategies render views in one of two ways, and the difference decides whether visual
effects appear in your snapshots:

  * By default, snapshots are captured with
    [`CALayer.render(in:)`](https://developer.apple.com/documentation/quartzcore/calayer/render(in:)),
    which draws the view's own layer tree into a bitmap. It runs entirely inside the test process
    and needs no host application.
  * With `drawHierarchyInKeyWindow: true` (available on the `image` strategies for `UIView`,
    `UIViewController`, and SwiftUI views), snapshots are captured with
    [`UIView.drawHierarchy(in:afterScreenUpdates:)`](https://developer.apple.com/documentation/uikit/uiview/drawhierarchy(in:afterscreenupdates:)),
    which renders "a snapshot of the complete view hierarchy as visible onscreen" — that is, what
    the system's render server actually composites.

Visual effects are not part of the view's own layer tree. Materials such as `UIVisualEffectView`
blurs, and on iOS 26 and later the Liquid Glass effects behind system controls, navigation bars,
`.searchable` fields, and `glassEffect`/`.glassProminent` styles, are composited out of process by
the render server. `CALayer.render(in:)` never sees them: the affected regions come out
transparent, blank, or with invisible foreground content, even though the rest of the layout is
correct. Because iOS 26 applies Liquid Glass to most system chrome, this affects nearly any
snapshot that includes navigation or toolbar UI, not just views that opt into glass explicitly.

`ImageRenderer` is not a way around this either: Apple documents that
[`ImageRenderer`](https://developer.apple.com/documentation/swiftui/imagerenderer) "does not
render views provided by native platform frameworks (AppKit and UIKit) such as web views, media
players, and some controls".

## Requirements for capturing effects

To snapshot a view whose appearance depends on the render server, all of the following must hold:

  1. **The test target must run in a host application.** Only an application process has a
     connection to the render server. In a host-less test bundle (for example, a Swift package
     test target), `drawHierarchy(in:afterScreenUpdates:)` has nothing to composite and returns
     `false` — Apple documents the `false` return as the snapshot "missing image data for any view
     in the hierarchy", which in practice is an entirely black frame.
  2. **The strategy must opt in**, for example:

     ```swift
     assertSnapshot(
       of: viewController,
       as: .image(drawHierarchyInKeyWindow: true)
     )
     ```

If the flag is set but no host application is present, the library records a test failure and
falls back to a host-less `CALayer.render(in:)` capture, so the failure's attached image still
shows the layout. Similarly, if `drawHierarchy(in:afterScreenUpdates:)` reports an incomplete
capture, the test fails rather than comparing or recording an image that is known to be missing
content.

## Configuring the host application

A window-drawn capture composites over the host application's own window: any pixels the view
under test does not cover show whatever the host has on screen. To keep references deterministic,
prefer a minimal, dedicated host over your real application — for example an app target whose
entire scene is:

```swift
@main
struct SnapshotHostApp: App {
  var body: some Scene {
    WindowGroup { EmptyView() }
  }
}
```

Then set that app as the **Host Application** of your snapshot test target (the `TEST_HOST` build
setting). If the same test target also builds for platforms where the flag is unavailable or
unnecessary, `TEST_HOST` can be scoped per SDK so only the iOS run is hosted.

## Determinism

Window-drawn captures sample the live Core Animation timeline, unlike `CALayer.render(in:)`. A
few practical consequences:

  * Views with ongoing animation (activity indicators, blinking text-field carets) can capture a
    different frame on every run. Disabling animations in the host process (for example,
    `UIView.setAnimationsEnabled(false)`) before capturing restores determinism.
  * Some system chrome, such as toolbar items, is installed a runloop turn after the hierarchy
    joins the window. Combining the strategy with `.wait(for:on:)` lets it land before capture.
  * Glass compositing can leave a small amount of per-run pixel noise. If exact matches prove
    flaky, `precision` and `perceptualPrecision` on the image strategy absorb it.

## Topics

### Related strategies

- ``Snapshotting``
