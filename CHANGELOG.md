# Changelog

Notable changes to MacView. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/). MacView ships as a signed,
notarized DMG; each released version gets a section here.

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
