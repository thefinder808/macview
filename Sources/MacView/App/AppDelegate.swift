import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Disable AppKit's automatic window tabbing before the main menu loads — a
    // single-window viewer never wants the Tab Bar menu items (and setting it
    // late makes them flicker on first menu open).
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    // A viewer should quit when its window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
