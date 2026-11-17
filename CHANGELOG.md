# Changelog

Notable changes to MacView. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/). MacView ships as a signed,
notarized DMG; each released version gets a section here.

## [Unreleased]

### Added
- **SVG support, properly.** SVGs already opened, but the rest of the app didn't
  know about them:
  - Filmstrip thumbnails now render for SVG files (they were blank).
  - The info overlay shows an SVG's dimensions.
  - Rotating an SVG keeps it a vector — sharp at any zoom, and the zoom percent
    no longer jumps.
  - Fit scales small SVGs (icons) **up** to fill the window. Photos still never
    upscale past 100%.
  - "Set as Default Image Viewer" now includes SVG, and SVG is declared in the
    app's document types.

### Fixed
- The toolbar zoom readout no longer wraps onto two lines at 1,000% and above.

## [1.1.0] — 2026-07-27

### Added
- **Automatic updates via Sparkle 2** — "Check for Updates…" in the app menu and
  a Software Updates section in Settings (auto-check daily by default). Updates
  are EdDSA-signed and served from the repo's `gh-pages` feed. The app version
  is now derived from the latest `v*` git tag at build time.

### Fixed
- Filmstrip thumbnails load lazily — opening an image in a very large folder no
  longer decodes a thumbnail for every file up front.
- The thumbnail cache is bounded (LRU, 256 entries) so huge folders can't grow
  memory without limit.
- Info overlay dimensions for EXIF-rotated photos (portrait phone shots) now
  match the displayed orientation instead of the stored one.
- Smoother paging while holding an arrow key: neighbor prefetch no longer queues
  a whole batch ahead of the next image's decode, and stops once navigation has
  moved on.

### Removed
- Dead code: the unused `ImageItem` model (file renamed to `ImageInfo.swift`)
  and `DefaultViewer.isDefaultForJPEG`.

## [1.0.0] — 2026-06-26 (first release)

### Added
- **Folder paging** — open one image and page through every image in its folder
  in Finder's natural order, via arrow keys, on-screen chevrons, two-finger
  trackpad swipe, or the bottom thumbnail filmstrip. Stops at the ends.
- **Viewing** — fit-to-window on open (never upscaling small images), zoom & pan
  (⌘± / pinch / ⌘-scroll / double-click / drag), click-to-hide chrome, dark
  chrome with a hidden title bar, and fullscreen.
- **Image actions** — non-destructive rotate, delete-to-Trash (with a confirm
  prompt and auto-advance), Copy (⌘C), Reveal in Finder (⌘⇧R), and a Share button.
- **Info overlay** (⌘I) with dimensions, file size, type, and basic EXIF.
- **Set as Default Image Viewer** from Settings.
- **Remembers** its window size and position across launches.
- **Broad format support** via ImageIO: JPEG, PNG, animated GIF, TIFF, BMP,
  HEIC/HEIF, WebP, AVIF, and camera RAW.
