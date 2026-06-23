# MacView Architecture

A single-window SwiftUI + AppKit app, Swift Package Manager only (no `.xcodeproj`),
macOS 14+, no third-party dependencies. Division of labor: **SwiftUI** owns layout,
state, and chrome; **AppKit** owns the image canvas, where precise zoom/pan and
large-image handling matter.

## Layers

```
App/        MacViewApp (@main, Window + menu commands), AppDelegate,
            SettingsManager, WindowAccessor (dark window chrome)
Models/     ImageItem (URL wrapper), ImageInfo (overlay metadata)
ViewModels/ ViewerModel — the single source of truth for the session
Services/   FolderScanner, ImageLoader (actor), Thumbnailer (actor),
            MetadataReader, FileActions (trash)
Views/      ContentView (ZStack), ImageCanvas (NSViewRepresentable + canvas),
            ViewerToolbar, Filmstrip, InfoOverlay, NavChevrons, SettingsView
Utilities/  Color+Hex / Palette, NSImage+Rotation
```

## Data flow

1. A file arrives via `onOpenURL` (Finder/Open With), the ⌘O panel, or drag-drop.
2. `ViewerModel.open(url:)` asks `FolderScanner` for all image siblings in the
   parent folder, natural-sorted, and locates the opened file's index.
3. `loadCurrent()` decodes the current image off-main through the `ImageLoader`
   actor, publishes it as `displayImage`, and prefetches ±2 neighbors. A
   `loadToken` guards against a stale decode landing after a newer navigation.
4. `ContentView` layers the AppKit canvas under SwiftUI chrome in a `ZStack`.
5. The canvas (`ZoomableImageScrollView`) reports its zoom percentage back to the
   `CanvasController`, which the toolbar observes.

## Key design decisions

- **AppKit canvas, not SwiftUI Image.** `ZoomableImageScrollView` is an
  `NSScrollView` (`allowsMagnification`) wrapping an `NSImageView`, with a
  `CenteringClipView` so small images sit centered on the backdrop. This gives
  pinch/⌘-scroll zoom, fit math, and smooth large-image rendering for far less
  code than reimplementing it with SwiftUI gestures. The document view's frame is
  set to the image's **pixel** size, so magnification 1.0 == 100% and fit math is
  exact.

- **Fit never upscales.** `fitMagnification()` is `min(scale-to-fit, 1.0)` — large
  images downscale to fit; small images show at 100%, centered.

- **Keyboard via a local event monitor, not first responder.** SwiftUI's hosting
  view keeps first-responder status, so a `keyDown` override on the AppKit canvas
  never fires (the view still gets *mouse* events via hit-testing — that mismatch
  is the tell). `viewDidMoveToWindow` installs an `NSEvent.addLocalMonitorForEvents`
  that routes ←/→/Space/⌫/Esc while our window is key and no sheet is attached.

- **Live zoom percent lives on `CanvasController` (ContentView scope), not the
  ViewModel (App scope).** It changes on every pinch tick; an App-scoped publisher
  would rebuild the `commands` menu each tick and make menu items vanish mid-track.
  `CanvasController` is held by the App as `@State` (a stable reference, *not*
  observed), so its updates never re-evaluate the App scene.

- **Rotation is non-destructive.** `rotateLeft/Right` adjust a `rotation` value;
  `NSImage.rotatedClockwise` renders a pixel-preserving rotated copy for display.
  The file on disk is never modified.

- **Delete is recoverable.** `FileManager.trashItem` (macOS Trash), gated by an
  optional confirm prompt, then auto-advance to the next image.

- **Sandbox off.** Direct (Developer ID) distribution; reading sibling files in a
  folder needs no security-scoped bookmarks, which is what makes paging work.

## Build / distribution

`build.sh` assembles the `.app` (binary + generated `Info.plist` declaring image
`CFBundleDocumentTypes` + `AppIcon.icns` from the committed iconset), signs it
(ad-hoc for dev, Developer ID for release), and can build/notarize/staple a DMG.
No Sparkle / auto-update in v1.
