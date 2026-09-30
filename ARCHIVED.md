# Archived: perceptual-diagnostics

This branch is archived and kept only as the tag `archive/perceptual-diagnostics`. It is not
maintained and is not merged anywhere.

## What it held

Investigation work on the perceptual image comparison, written while chasing an intermittent
`perceptualPrecision` failure on iOS:

- counting the failing pixels exactly instead of deriving the count from an area average;
- a 16-bit normalized component diff for the difference image;
- passing the extent to `CIAreaAverage` / `CIAreaMaximum` as a `CIVector`;
- an earlier draft of the "Reading a precision failure" article and its tests.

## Why it was archived

- The failure turned out to be a colour-space mismatch, not a counting problem: the perceptual
  comparison received the un-normalized images. That fix was reworked into a small, separate
  change and lives on `perceptual-colorspace-fix`, which the fork branches merge.
- The exact-count and 16-bit diff changes were not needed for that fix and were dropped from
  the reworked history.
- The `CIVector` extent change is now upstream (pointfreeco/swift-snapshot-testing#1120).
- The branch is based on history that was rewritten, so it cannot be merged cleanly into the
  current branches.
