import SwiftUI

// Not `@main`: `Main` runs first so a `VectorProbe` child launch never starts the app.
struct MacViewApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ViewerModel()
    @StateObject private var settings = SettingsManager.shared
    // Safe on the App scene despite the "high-frequency publishers" gotcha:
    // canCheckForUpdates flips rarely (never per-tick), same as macpad.
    @StateObject private var updater = UpdaterService()
    // CanvasController is held as @State, NOT @StateObject: it publishes the
    // live zoom percent on every pinch tick, and an App-observed object would
    // rebuild the menu (`commands`) on each tick. @State keeps a stable
    // reference without subscribing the App scene to its changes.
    @State private var canvas = CanvasController()

    var body: some Scene {
        Window("MacView", id: "main") {
            ContentView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(canvas)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1100, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            // "Check for Updates…" under the app menu, next to "About MacView".
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }

            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.openWithPanel() }
                    .keyboardShortcut("o")
                Button("Reveal in Finder") { model.revealInFinder() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.isEmpty)
            }

            CommandGroup(replacing: .pasteboard) {
                Button("Copy") { model.copyToClipboard() }
                    .keyboardShortcut("c")
                    .disabled(model.isEmpty)
            }

            CommandGroup(after: .toolbar) {
                Button("Zoom In") { canvas.zoomIn() }.keyboardShortcut("=")
                Button("Zoom Out") { canvas.zoomOut() }.keyboardShortcut("-")
                Button("Zoom to Fit") { canvas.fit() }.keyboardShortcut("0")
                Button("Actual Size") { canvas.actualSize() }.keyboardShortcut("1")
                Divider()
                Button(model.infoVisible ? "Hide Info" : "Show Info") { model.toggleInfo() }
                    .keyboardShortcut("i")
                Button(model.filmstripVisible ? "Hide Filmstrip" : "Show Filmstrip") {
                    model.toggleFilmstrip()
                }
            }

            CommandMenu("Image") {
                Button("Next") { model.next() }.disabled(!model.hasNext)
                Button("Previous") { model.previous() }.disabled(!model.hasPrevious)
                Divider()
                Button("Rotate Left") { model.rotateLeft() }
                    .keyboardShortcut("l").disabled(model.isEmpty)
                Button("Rotate Right") { model.rotateRight() }
                    .keyboardShortcut("r").disabled(model.isEmpty)
                Divider()
                Button("Move to Trash") { model.requestDelete() }.disabled(model.isEmpty)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(updater)
        }
    }
}
