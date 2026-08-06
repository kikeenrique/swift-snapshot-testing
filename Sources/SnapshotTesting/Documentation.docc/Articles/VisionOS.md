# Snapshot testing on visionOS

What a visionOS snapshot can capture, what it cannot, and why — with references to Apple's
documentation for each claim.

## Window geometry

visionOS publishes no fixed window bounds: the system opens windows at a default size, but the
[Human Interface Guidelines ask each app to choose its own minimum and maximum][hig-windows], and
windows are freely resizable by the wearer (see [Positioning and sizing windows][sizing-windows]).
The `visionOSWindow` config therefore describes the system's initial window size (1280×720 pt at
2×), and `visionOSWindow(width:height:)` accepts any other geometry.

```swift
assertSnapshot(of: vc, as: .image(on: .visionOSWindow))
assertSnapshot(of: vc, as: .image(on: .visionOSWindow(width: 1920, height: 1080)))
```

[hig-windows]: https://developer.apple.com/design/human-interface-guidelines/windows#visionOS
[sizing-windows]: https://developer.apple.com/documentation/visionOS/positioning-and-sizing-windows

## Dynamic colors resolve dark by default

visionOS has no user-facing appearance setting: the HIG's [Materials][hig-materials] page states
"visionOS doesn't have a distinct Dark Mode setting. Instead, glass automatically adapts to the
luminance of the objects and colors behind it." In a snapshot render there is no glass and no
surroundings, and unpinned dynamic colors resolve as dark — `.label` renders white and
`.systemBackground` clear — so a reference recorded without an explicit appearance looks
surprisingly dark or blank. Pass the appearance you mean at the call site:

```swift
assertSnapshot(
  of: vc,
  as: .image(on: .visionOSWindow, traits: .init(userInterfaceStyle: .light))
)
```

[hig-materials]: https://developer.apple.com/design/human-interface-guidelines/materials

## System-composited content cannot be captured

A snapshot is an in-process render: the library draws the view with
[`CALayer.render(in:)`][render-in] — which, per its documentation, "renders directly from the
layer tree" — or with [`UIView.drawHierarchy(in:afterScreenUpdates:)`][draw-hierarchy], whose own
return value acknowledges that a capture can be "missing image data" for views it cannot see.

On visionOS the pixels a wearer actually sees are produced *outside* the app's process. Apple's
[Understanding the visionOS render pipeline][render-pipeline] describes the architecture: apps only
send layer-tree and RealityKit updates to a shared render server (`backboardd`), which "receives
updates from all the running apps … and composites them into a single drawable image"; the
compositor then "processes data about your surroundings from Apple Vision Pro sensors and cameras"
and blends everything for display. An in-process capture can therefore only ever contain what the
app itself draws. Concretely:

- **Glass and vibrancy.** Glass is "an unmodifiable system-defined material" whose appearance
  adapts "depending on people's physical surroundings and other virtual content"
  ([HIG: Materials][hig-materials]) — its pixels are a function of the wearer's room, which does
  not exist in a test render. The SwiftUI modifier is likewise documented as adding "a 3D glass
  background material" whose "physical depth … influences z-axis layout"
  ([`glassBackgroundEffect(displayMode:)`][glass-effect]) — 3D geometry the system draws, not
  layer content.
- **Ornaments.** An ornament "floats in a plane that's parallel to its associated window and
  slightly in front of it along the z-axis" ([HIG: Ornaments][hig-ornaments]) — it is not part of
  the window's view hierarchy at all.
- **RealityKit content.** What a `RealityView` displays is rendered by the shared render server,
  not by the app ([Understanding the visionOS render pipeline][render-pipeline]). The one partial
  exception: [`RealityRenderer`][reality-renderer] can rasterize a RealityKit scene "in an existing
  Metal workflow" — a separate, dedicated rendering path, not a capture of what `RealityView`
  shows on device.

A snapshot of such content coming back empty is a platform boundary, not a bug in the library.

[render-in]: https://developer.apple.com/documentation/quartzcore/calayer/render(in:)
[draw-hierarchy]: https://developer.apple.com/documentation/uikit/uiview/drawhierarchy(in:afterscreenupdates:)
[render-pipeline]: https://developer.apple.com/documentation/visionos/understanding-the-visionos-render-pipeline
[glass-effect]: https://developer.apple.com/documentation/swiftui/view/glassbackgroundeffect(displaymode:)
[hig-ornaments]: https://developer.apple.com/design/human-interface-guidelines/ornaments
[reality-renderer]: https://developer.apple.com/documentation/realitykit/realityrenderer

## What to do instead

Snapshot the content with the glass or vibrancy effect disabled, which still pins layout, sizing,
and text; and keep visionOS snapshots to app-rendered 2D content.

If you need to see the system-composited result itself, capture from outside the process: UI-test
screenshots ([`XCUIScreen`][xcui-screen], [`XCUIScreenshot`][xcui-screenshot]) and
`xcrun simctl io booted screenshot` record the compositor's output, so glass, ornaments, and
RealityKit content are in the pixels. They are a complement, not a replacement: the capture is a
perspective projection of your window in a simulated room — glass deliberately lets the
surroundings show through ([HIG: Materials][hig-materials]) — so the pixels vary with environment,
window placement, and pose, and each shot needs the full app running under a UI-test target. Use
them for a few end-to-end "does the chrome appear" checks, and in-process snapshots for precise,
isolated regression coverage of app-drawn content.

[xcui-screen]: https://developer.apple.com/documentation/xctest/xcuiscreen
[xcui-screenshot]: https://developer.apple.com/documentation/xctest/xcuiscreenshot
