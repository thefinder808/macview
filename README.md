# MacView

A simple, sleek, efficient macOS image viewer — built to bring the **Windows 11
Photos** "page through the folder" experience to the Mac. Open one image and use
Next/Previous (arrow keys or on-screen chevrons) to flip through every other
image in that folder, the way Preview never quite let you.

> Not affiliated with Microsoft or Windows. "Windows 11" is referenced only to
> describe the interaction model this app emulates.

## Features

- **Folder as album** — open one image, page through the whole folder in Finder's
  natural (numeric-aware) order. Stops at the ends.
- **Open by drag-and-drop** — drop an image onto the window (or the app icon) to
  start paging its folder; or ⌘O / "Open With".
- **Fit-to-window** on open, never upscaling small images past 100%.
- **Fast zoom & pan** — ⌘+ / ⌘−, trackpad pinch, ⌘-scroll, double-click to toggle
  fit ⇄ 100%, drag to pan. Live zoom-percent readout.
- **Click to hide chrome** — one click on the image hides the toolbar, chevrons,
  and filmstrip for a distraction-free view; click again to bring them back.
- **Bottom filmstrip** of folder thumbnails; click any to jump.
- **Two-finger swipe** left/right to page between images.
- **Rotate** left/right (non-destructive — never rewrites your file).
- **Delete to Trash** with a confirm prompt, then auto-advance to the next image.
- **Copy** (⌘C), **Reveal in Finder** (⌘⇧R), and a **Share** button (AirDrop, Messages, Mail, Add to Photos, …).
- **Info overlay** — dimensions, file size, type, and basic EXIF (⌘I).
- **Remembers** its window size and position across launches.
- **Broad format support** via macOS ImageIO: JPEG, PNG, GIF (animated plays
  inline), TIFF, BMP, HEIC/HEIF, WebP, AVIF, and camera RAW.
- **Sleek dark** chrome with a hidden title bar; fullscreen support.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open… | ⌘O |
| Next / Previous image | → / ← |
| Toggle chrome | Space |
| Zoom in / out | ⌘+ / ⌘− |
| Zoom to fit | ⌘0 |
| Actual size (100%) | ⌘1 |
| Toggle fit ⇄ 100% | double-click |
| Rotate left / right | ⌘L / ⌘R |
| Info overlay | ⌘I |
| Copy image | ⌘C |
| Reveal in Finder | ⌘⇧R |
| Move to Trash | ⌫ |
| Full screen | ⌃⌘F (or the toolbar button; Esc exits) |

## Install

Download the latest `MacView-x.y.z.dmg` from Releases, open it, and drag MacView
to Applications.

To make it your default image viewer, either:
- open **MacView → Settings (⌘,) → "Set MacView as the Default Image Viewer"**, or
- right-click an image in Finder → **Open With → Other… → MacView**, check "Always Open With".

(Install to /Applications first so the association points at a stable location.)

## Build from source

Requires macOS 14+ and the Swift toolchain (Xcode or Command Line Tools).

```bash
git clone <repo-url> macview && cd macview
./build.sh run        # build a .app bundle and launch it
```

Other `build.sh` subcommands: `app` (assemble bundle), `open` (launch via
LaunchServices), `release` / `install` (to /Applications), `dmg`, `clean`.

### Regenerate the icon

```bash
pip3 install pillow
python3 tools/make_icon.py   # rewrites Resources/AppIcon.iconset; build.sh makes the .icns
```

### Signed, notarized release

```bash
brew install create-dmg
./build.sh notarize   # Developer ID sign + DMG + notarize + staple
```

Uses the shared `traceview-notary` keychain profile. See `CLAUDE.md` for details.

## Architecture

SwiftUI owns layout, state, and chrome; AppKit (an `NSScrollView` with
magnification) owns the image canvas for efficient zoom/pan and large-image
handling. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the layer map and
design decisions, [CLAUDE.md](CLAUDE.md) for conventions and hard-won gotchas, and
[CHANGELOG.md](CHANGELOG.md) for version history.

## Support

If MacView is useful to you: [Buy me a coffee](https://www.buymeacoffee.com/thefinder808) ☕

## License

MIT — see [LICENSE](LICENSE).
