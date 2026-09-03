# Reading a precision failure

Learn what `precision` and `perceptualPrecision` each measure, and how to tell a real change from
a color-space mismatch.

## Overview

When an image snapshot fails and either `precision` or `perceptualPrecision` is below `1`, the
failure message carries two numbers:

```
The percentage of pixels that match 0.97958946 is less than required 1.0
The lowest perceptual color precision 0.8128 is less than required 0.98
```

They answer different questions. The first is an area: the fraction of pixels whose
[CIE Delta E](http://zschuessler.github.io/DeltaE/learn/#toc-defining-delta-e) is within the
perceptual bar, so the pixel count is recoverable from it.

```
failingPixels = (1 - reportedPrecision) * width * height
```

The second is not an area at all. It is `1 - maximumDeltaE / 100` for the single worst pixel in
the image, and says nothing about how many pixels are wrong. A Delta E of about 1 is the threshold
of human perceptibility; 19 is an obvious color change.

Because one is an average over the frame and the other a maximum, they move independently. A very
high `precision` beside a low `perceptualPrecision` is the signature of a small, localized change
— an antialiased edge that shifted by a subpixel replaces a blended edge pixel with the color on
the other side of the edge, which is a large Delta E on a handful of pixels.

## When the failure is not a change at all

A perceptual failure can also mean the two images were never compared in the same color space. On
iOS a `UIGraphicsImageRenderer` render is extended sRGB, 16 bits per component, floating point;
its own PNG round trip — the reference as it is written to disk and read back — is Display P3, 16
bits per component, integer. The perceptual comparison runs `CILabDeltaE` with color management
disabled, so it reads raw component values; handed those two images un-normalized, it reports a
large Delta E on every saturated pixel even though nothing on screen has changed.

Saturated colors move furthest between color spaces, while paper white and black text barely move
at all, so the failing region is the screen's strongly-colored elements and only those. One
reported screen's single saturated button covered 2.1 % of the frame, and the failure reported
2.04 % of pixels differing with a lowest perceptual precision of 0.8128 — the same two numbers on
every run.

It was intermittent for a reason worth knowing. Both strategies compare the images byte for byte
first, and return early when those bytes match, so a byte-stable render never reaches the
perceptual comparison. Only when sub-code-point jitter on one glyph tripped the byte comparison
did a run reach the perceptual path, and from there the answer was wrong every time. Both
strategies now normalize the two images into the same sRGB 8-bit space before comparing them
perceptually.

## Topics

### Related strategies

- ``Snapshotting``
