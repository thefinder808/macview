# CLAUDE.md — MacView

A simple macOS image viewer that emulates the Windows 11 Photos "page through the
folder" model. SwiftUI + AppKit, Swift Package Manager only, macOS 14+, **no
third-party dependencies**. See `docs/ARCHITECTURE.md` for the full layout.

## Conventions (match the fleet: macpad / MacPerf / TraceView)

- **SPM, no `.xcodeproj`.** `swift build`; `./build.sh {build|run|app|open|release|install|dmg|notarize|clean}`.
- **No xcassets.** Colors via `Color(hex:)` / `Palette` (`Utilities/Color+Hex.swift`).
- **Bundle id** `com.macview.app`; binary/product `MacView`.
- **Icon** is generated: `tools/make_icon.py` (Pillow) writes `Resources/AppIcon.iconset`
  (committed); `build.sh` runs `iconutil` to make `AppIcon.icns` (gitignored).
  Rounded-rect plate at the **0.2249** corner ratio, ~100px margin on 1024, flat
  near-black plate — per the fleet icon gotchas.
- **Signing/notarization**: Developer ID `Nathaniel Graham (Q6LRJQSA42)`, shared
  `traceview-notary` keychain profile. DMG distribution (no Installer cert). No
  Sparkle — distribution is a plain notarized DMG; auto-update is a possible v2.
- **Sandbox off** (`Resources/MacView.entitlements`) so the viewer can read sibling
  files in a folder for paging without security-scoped bookmarks.
- **Info.plist** (generated in `build.sh`) declares image `CFBundleDocumentTypes`
  with `LSHandlerRank = Alternate` so MacView appears in "Open With" and can be set
  as default without seizing the association from Preview.

## Gotchas hit while building this (don't relearn them)

- **AppKit canvas key events need a local event monitor, not first responder.**
  SwiftUI's hosting view keeps first-responder status, so a `keyDown` override on
  the `NSScrollView` canvas never fires — even though the same view receives
  *mouse* events fine (hit-testing, independent of first responder). That
  mouse-works/keys-don't split is the diagnostic. Fix: `viewDidMoveToWindow`
  installs `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` that routes
  ←/→/Space/⌫ (and Esc *only* to leave fullscreen — passed through otherwise) while
  our window `isKeyWindow` and `attachedSheet == nil` (so the delete-confirm dialog
  keeps its own key handling). See `Sources/MacView/Views/ImageCanvas.swift` (`keyMonitor`).

- **Bare SwiftUI controls over the AppKit canvas don't receive clicks.** An
  embedded `NSView` (the `NSScrollView` canvas) wins AppKit hit-testing against
  SwiftUI shapes drawn over it, regardless of ZStack z-order. Symptom: clicking
  the nav chevrons just toggled the chrome (the click fell through to the canvas).
  The tell: the **toolbar and filmstrip worked** because their container-level
  `.ultraThinMaterial` background materializes a real hit-testable `NSView`;
  bare chevrons had none. `.background(ImageCanvas)` instead of a ZStack sibling
  did NOT work (the representable renders blank as a background layer). The robust
  fix: don't rely on SwiftUI hit-testing for controls over the canvas — the canvas
  reliably gets those clicks, so it computes a left/center/right **`ClickZone`**
  from the click x and reports it; `ViewerModel.handleClick` navigates on edge
  clicks (chrome visible) or toggles chrome. The chevrons are visual-only
  (`allowsHitTesting(false)`). See `ImageCanvas.swift` (`zone(for:)`) and
  `NavChevrons.swift`. Material-backed overlays (toolbar/filmstrip/info) keep
  handling their own clicks normally.

- **Two-finger swipe paging has four traps (`ImageCanvas.swift` `scrollWheel`).**
  This is the third canvas-owned navigation path (alongside the key monitor and
  `ClickZone`), wiring `onPrevious`/`onNext`. (1) **Drop the momentum tail** —
  `if event.momentumPhase != [] { return }` — or the inertial glide after the
  finger lifts pages through several images for a second or two (this was the live
  bug). (2) **Only page when the image can't pan horizontally**
  (`displayedWidth > bounds.width + 1`), else a zoomed image should pan instead.
  (3) **One page-turn per gesture** — a `swipeNavigated` flag + a 50pt accumulated
  `swipeAccumX` threshold. (4) **Direction matches the macOS Spaces gesture** — a
  left swipe advances to the *next* image; in code that's `swipeAccumX > 0 →
  onPrevious`, `< 0 → onNext` (the sign reflects natural-scrolling `deltaX`). If a
  user reports it reversed, that one comparison is the flip. Phase-less line scrolls
  (mouse wheel) start a fresh gesture after a 0.18s pause.

- **Don't move ←/→/⌫ onto menu-item `.keyboardShortcut`s.** They're handled by the
  key monitor on purpose: a bare-arrow key equivalent on a menu item flashes the
  menu-bar title on every press, which is miserable when arrowing through photos.

- **Keep high-frequency publishers off the App scene, or menus vanish.** The live
  zoom percent changes on every pinch/scroll tick. It lives on `CanvasController`
  (held by ContentView as `@ObservedObject`), and the App holds `CanvasController`
  as **`@State`** (stable reference, not observed) — so zoom ticks never
  re-evaluate `MacViewApp.body` / the `commands` block. Putting it on the
  App-scoped `ViewerModel` would rebuild the menu each tick and cancel menu
  tracking (the fleet's "menu items vanish" bug). This is why `ViewerModel` has no
  `zoomPercent`.

- **`.windowStyle(.hiddenTitleBar)` drops the fullscreen capability.**
  `toggleFullScreen` is a silent no-op until you re-add it:
  `window.collectionBehavior.insert(.fullScreenPrimary)` in `WindowAccessor`.
  Symptom: ⌃⌘F and the fullscreen toolbar button do nothing.

- **Display the image at pixel size for exact zoom math.** The canvas sets
  `imageView.frame` to the image's pixel dimensions (from the first rep), so
  magnification 1.0 == 100% and `fit = min(scale, 1.0)` cleanly "fits without
  upscaling small images."

- **Rotation is non-destructive by design (v1).** `ViewerModel.rotation` + a
  pixel-preserving `NSImage.rotatedClockwise` copy for display; the file is never
  rewritten. Lossless save-to-file rotation is a deliberate v2 (avoids JPEG
  re-encode + read-only-file edge cases).

## Verifying GUI changes

`./build.sh open`, then drive via computer-use granting by **bundle id
`com.macview.app`** (granting by display name fails for a non-installed dev
build). Launch the dev build by full path so it isn't confused with any installed
copy. A scratch folder of numbered images (`1.png`, `2.jpg`, … `10.png`, plus an
animated `5.gif`) tests natural sort (1,2,3,…,10 not 1,10,2) and GIF playback.
