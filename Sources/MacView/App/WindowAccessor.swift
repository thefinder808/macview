import SwiftUI
import AppKit

/// Reaches the hosting NSWindow to give MacView its sleek dark chrome: a
/// transparent, hidden title bar over a near-black background, dark appearance,
/// and the current filename as the (hidden but accessible) window title.
struct WindowAccessor: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false   // don't fight canvas drag-to-pan
        // hiddenTitleBar can drop the fullscreen capability; re-enable it so
        // ⌃⌘F and the toolbar's fullscreen button work.
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.backgroundColor = NSColor(red: 0x10 / 255, green: 0x10 / 255, blue: 0x12 / 255, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = title.isEmpty ? "MacView" : title
    }
}
