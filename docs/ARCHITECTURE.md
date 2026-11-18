# MacView Architecture

A single-window SwiftUI + AppKit app, Swift Package Manager only (no `.xcodeproj`),
macOS 14+, with Sparkle (auto-update) as the only third-party dependency. Division
of labor: **SwiftUI** owns layout, state, and chrome; **AppKit** owns the image
canvas, where precise zoom/pan and large-image handling matter.

## Layers

```
App/        MacViewApp (@main, Window + menu commands), AppDelegate,
            SettingsManager, WindowAccessor (dark chrome + fullscreen + frame autosave),
            UpdaterService (Sparkle wrapper: check-for-updates + 4012 TCC alert)
Models/     ImageInfo (overlay metadata)
ViewModels/ ViewerModel — the single source of truth for the session
Services/   FolderScanner, ImageLoader (actor), Thumbnailer (actor), MetadataReader,
            FileActions (trash), DefaultViewer (register as default image viewer)
Views/      ContentView (ZStack), ImageCanvas (NSViewRepresentable + canvas),
            ViewerToolbar, Filmstrip, InfoOverlay, NavChevrons, SettingsView
Utilities/  Color+Hex / Palette, NSImage+Rotation, NSImage+Vector (SVG helpers)
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
6. Navigation reaches `ViewerModel` from four surfaces: the canvas key monitor
   (←/→), edge clicks resolved to a `ClickZone` (`handleClick`), a two-finger
   horizontal swipe (canvas `scrollWheel`), and filmstrip tap-to-jump. The on-screen
   chevrons are visual-only — see the ClickZone decision below.

## Key design decisions

- **AppKit canvas, not SwiftUI Image.** `ZoomableImageScrollView` is an
  `NSScrollView` (`allowsMagnification`) whose document view is an `NSImageView`
  for bitmaps (it also plays animated GIFs) or a `VectorImageView` for vectors —
  `setImage` swaps them — with a `CenteringClipView` so small images sit
  centered on the backdrop. This gives
  pinch/⌘-scroll zoom, fit math, and smooth large-image rendering for far less
  code than reimplementing it with SwiftUI gestures. The document view's frame is
  set to the image's **pixel** size, so magnification 1.0 == 100% and fit math is
  exact.

- **Fit never upscales bitmaps.** `fitMagnification()` is `min(scale-to-fit, 1.0)` —
  large images downscale to fit; small images show at 100%, centered. Vectors
  (`NSImage.isVector`) are the exception: they scale up to fill the window, capped
  at `maxMagnification`.

- **SVG rides on AppKit, not ImageIO.** ImageIO has no SVG decoder
  (`CGImageSourceCreateThumbnailAtIndex` and the properties call both return nil),
  but `NSImage(contentsOf:)` loads SVG as a vector rep. So the canvas needed
  nothing, and the ImageIO-based services fall back: `Thumbnailer` draws the
  `NSImage` into a ≤200px bitmap (`NSImage.rasterized(maxPixel:)`), and
  `MetadataReader` reports the `NSImage`'s nominal size as the dimensions.
  `NSImage.isVector` (first rep reports no pixel size) is the one test the canvas
  and rotation use. See `Utilities/NSImage+Vector.swift`.

- **An SVG's declared size is untrusted input.** A file can claim `width="1e40"`,
  and `NSImageView` allocates a bitmap that size to draw it — AppKit throws and
  the app dies. `ImageLoader.decode` is the single place full images are decoded,
  and it calls `NSImage.clampVectorSize()` (longest side ≤ 4096pt), so the canvas
  and rotation only ever see sane sizes. `MetadataReader` reports the *declared*
  size, converted with `Int(exactly:)` so an out-of-range value is skipped rather
  than trapping.

- **Vectors draw through `VectorImageView`, not `NSImageView`.** `NSImageView`
  rasterizes the *whole* vector at `size × magnification × backing scale`, so
  memory grows with the square of the zoom (a 1024pt SVG: 820 MB at 400%, past
  3 GB at 800%). `VectorImageView` is a plain `NSView` whose `draw(_:)` draws
  the image's first rep into its bounds. Under a magnified `NSScrollView`,
  AppKit backs only the **visible rect** of such a view (and replays the
  recorded drawing rather than calling `draw(_:)` again), so the cost is one
  viewport of pixels at any zoom: a 4096pt SVG at 4000% peaks at ~345 MB in a
  1372×895 window (measured in the app; a standalone spike with a display-sized
  1728×1085 window peaked ~445 MB, so the cost follows the window, not the
  zoom). SVGs using blur, turbulence, masks, patterns, group opacity, blend
  modes, clip paths and embedded images were ramped the same way and all stay
  flat with zoom. A live trackpad pinch to 4000% with panning (hand-driven, same
  4096pt SVG, 1340×848 window) peaked at 484 MB — the highest figure seen, and
  transient: it settled back to ~170 MB. Two rules keep it that way:
  draw the **rep**, not the `NSImage` (`NSImage.draw` goes through the image's
  bitmap cache and comes out blurry), and never put a vector back in an
  `NSImageView`. A `CATiledLayer` was also measured: sharp, but its tile cache
  climbed to ~660 MB while panning and it needs off-main drawing.

- **Known gap: SVG filter regions.** AppKit rasterizes a `<filter>`'s region at
  the image's nominal size whatever the output size, so the cost is paid on
  open — even for a 200px thumbnail — and does not depend on zoom or on which
  view draws it. On a 4096pt SVG a 150% region peaks ~2.4 GB in the canvas, a
  300% region ~2.4 GB in the thumbnailer, and a 2100% region passes 3 GB in
  both — so one such file in a folder can take the app down through the
  filmstrip. Not mitigated yet (`clampVectorSize` only limits the base size).

- **The zoom cap survives only where that is unmeasured.** `zoomCeiling(for:)`
  returns the plain 4000% ceiling for bitmaps, and for vectors on macOS 27+. The
  visible-rect backing is AppKit's behavior, verified on macOS 27.2 only, so on
  macOS 14–26 vectors keep the old pixel budget (32 MP) — the worst case there
  is the old, capped zoom, never runaway memory. Measure on an older system
  (watchdog on) before dropping the `#available` check.

- **Keyboard via a local event monitor, not first responder.** SwiftUI's hosting
  view keeps first-responder status, so a `keyDown` override on the AppKit canvas
  never fires (the view still gets *mouse* events via hit-testing — that mismatch
  is the tell). `viewDidMoveToWindow` installs an `NSEvent.addLocalMonitorForEvents`
  that routes ←/→/Space/⌫ (Esc only to exit fullscreen) while our window is key and
  no sheet is attached.

- **Edge-click navigation via `ClickZone`, not chevron buttons.** A bare SwiftUI
  control over the embedded `NSView` loses AppKit hit-testing, so chevron *buttons*
  would never get the click. Instead the canvas — which reliably receives the click —
  computes a left/center/right `ClickZone` (96pt edge band) and reports it via
  `onClick`; `ViewerModel.handleClick` navigates on an edge click (when chrome is
  visible) or toggles chrome on a center click. The chevrons are visual-only
  (`allowsHitTesting(false)`). Material-backed overlays (toolbar/filmstrip) keep
  their own clicks because their `.ultraThinMaterial` backing is a real NSView.

- **Two-finger swipe paging.** Horizontal trackpad scroll in the canvas
  `scrollWheel` pages between images, but only when the image can't pan horizontally
  (a zoomed image pans instead). It drops the post-lift momentum tail
  (`event.momentumPhase`), turns at most one page per gesture (accumulated-Δx
  threshold), and matches the macOS Spaces direction (left swipe → next).

- **Window state & fullscreen live in `WindowAccessor`.** Beyond the dark chrome, it
  re-inserts `.fullScreenPrimary` into `collectionBehavior` (which `.hiddenTitleBar`
  drops) and sets `setFrameAutosaveName`, so size/position persist across launches.

- **File actions.** Copy (⌘C) writes the displayed `NSImage` + file URL to the
  pasteboard; Reveal in Finder uses `NSWorkspace.activateFileViewerSelecting`; Share
  is a SwiftUI `ShareLink` on the toolbar; and the Settings pane's "Set as Default
  Image Viewer" calls `DefaultViewer.makeDefault` (per-UTI `NSWorkspace`
  registration). `FileActions` itself holds only the destructive `trash`.

- **Live zoom percent lives on `CanvasController` (ContentView scope), not the
  ViewModel (App scope).** It changes on every pinch tick; an App-scoped publisher
  would rebuild the `commands` menu each tick and make menu items vanish mid-track.
  `CanvasController` is held by the App as `@State` (a stable reference, *not*
  observed), so its updates never re-evaluate the App scene.

- **Rotation is non-destructive.** `rotateLeft/Right` adjust a `rotation` value;
  `NSImage.rotatedClockwise` renders a pixel-preserving rotated copy for display.
  The file on disk is never modified. A vector source gets an
  `NSCustomImageRep` that replays the source rep through a rotated transform,
  so the copy is still a vector and costs no more memory than the original
  (the earlier in-memory-PDF copy peaked ~160 MB higher on a 4096pt SVG).

- **Delete is recoverable.** `FileManager.trashItem` (macOS Trash), gated by an
  optional confirm prompt, then auto-advance to the next image.

- **Sandbox off.** Direct (Developer ID) distribution; reading sibling files in a
  folder needs no security-scoped bookmarks, which is what makes paging work.

## Build / distribution

`build.sh` assembles the `.app` (binary + generated `Info.plist` declaring image
`CFBundleDocumentTypes` + Sparkle `SU*` keys + `AppIcon.icns` from the committed
iconset), embeds `Sparkle.framework` into `Contents/Frameworks`, signs everything
inside-out (ad-hoc for dev, Developer ID for release — never `codesign --deep`),
and can build/notarize/staple a DMG. The version is derived from the latest `v*`
git tag (`MACVIEW_VERSION` overrides). `Package.resolved` is committed, so the
Sparkle version a release ships is the one in git. Auto-update is Sparkle 2: `UpdaterService`
(ported from macpad) drives `SPUStandardUpdaterController`; the EdDSA-signed
appcast + DMGs are generated by `./build.sh notarize` and pushed to the public
`gh-pages` branch by `./build.sh publish-appcast` (feed:
`https://thefinder808.github.io/macview/appcast.xml`).
