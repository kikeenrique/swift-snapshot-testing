# Reading a precision failure

Learn what `precision` and `perceptualPrecision` each measure, why a handful of pixels can report
a large color difference, and how to turn the reported fraction back into a pixel count.

## Overview

When an image snapshot fails and either `precision` or `perceptualPrecision` is below `1`, the
failure message carries two numbers:

```
The percentage of pixels that match 0.99997205 is less than required 1.0
The lowest perceptual color precision 0.8100000 is less than required 0.98
```

They answer different questions, and reading them as one number is the usual source of confusion.

## The first number: how many pixels differ

The first line is `precision`: the fraction of pixels whose color difference is *within* the
perceptual bar. It is derived by computing the
[CIE Delta E](http://zschuessler.github.io/DeltaE/learn/#toc-defining-delta-e) of every pixel,
counting the pixels whose Delta E exceeds `(1 - perceptualPrecision) * 100`, and dividing that
count by the total number of pixels:

```
precision = 1 - failingPixels / (width * height)
```

So the count is recoverable from the message. Multiply the shortfall by the pixel count of the
image on disk:

```
failingPixels = (1 - reportedPrecision) * width * height
```

For a 1170x2532 reference, `0.99997205` means `(1 - 0.99997205) * 2_962_440`, i.e. 83 pixels.
Against three million pixels, 83 is a hairline: a single antialiased edge that moved by a
fraction of a point.

> Note: The count is exact. It is a count of thresholded pixels, not an estimate derived from an
> image-wide average, so `(1 - precision) * width * height` always lands on a whole number of
> pixels up to `Float` rounding.

## The second number: how wrong the worst pixel is

The second line is `perceptualPrecision`, and it does **not** describe an area. It is the
perceptual precision of the single worst pixel in the image:

```
perceptualPrecision = 1 - maximumDeltaE / 100
```

A Delta E of about 1 is the threshold of human perceptibility; 19 is an obvious color change.
So `0.81` means one pixel somewhere in the image is off by a Delta E of 19 — and says nothing
about how many pixels are.

Because it is a maximum, not an average, the two numbers move independently. The common shape of
a real failure is exactly the one above: a very high `precision` (almost no pixels differ) next to
a low `perceptualPrecision` (the few that do, differ a lot). Antialiased edges do this — a text
baseline or a rounded corner that shifts by a subpixel replaces a blended edge pixel with the
color on the other side of the edge, which is a large Delta E on a tiny number of pixels.

## When the failure is not a content change

A perceptual failure can also mean the two images were never compared in the same color space.
On iOS a `UIGraphicsImageRenderer` render is extended sRGB, 16 bits per component, floating
point; its own PNG round trip — the reference as it is written to disk and decoded back — is
Display P3, 16 bits per component, integer. The perceptual comparison runs `CILabDeltaE` with
color management switched off, so it reads raw component values. Handed those two images as they
arrive, it reports a large Delta E on every saturated pixel even though nothing on screen moved.

Saturated colors move furthest between color spaces; paper white and black text barely move at
all. So the failing region is the screen's strongly-colored elements and only those. One reported
screen's single olive button covers 2.1 % of the frame, and the failure reported 2.04 % of pixels
differing with a lowest perceptual precision of 0.8128 — the same two numbers on every run.

It was intermittent for a reason worth knowing: a byte-identical render never reaches the
perceptual comparison at all, because the byte comparison returns first. Only when sub-code-point
jitter on a magnifier glyph tripped that comparison did the run reach the perceptual path, and
from there it was wrong every time. `compareCore` now normalizes both images to the same sRGB
8-bit buffers before comparing them perceptually, which is what makes the reported fraction mean
what this article says it means.

## Choosing the two together

  * Lower `precision` to tolerate *how many* pixels may differ: `precision: 0.99` on a 1170x2532
    image forgives up to about 29,000 pixels — usually far more than you mean. Antialiasing noise
    normally needs three or four nines.
  * Lower `perceptualPrecision` to tolerate *how much* each pixel may differ: `0.98` is roughly
    the precision of the human eye, and is the right knob for color-management or compositing
    drift that shifts every pixel slightly.
  * A failure that reports high `precision` and low `perceptualPrecision` is a small, localized
    change. Read the `difference.png` attachment before relaxing either number: the difference is
    normalized against its own largest component difference, so even a sub-code-point delta shows
    up as visible pixels at the coordinates that actually moved.

## Topics

### Related strategies

- ``Snapshotting``
