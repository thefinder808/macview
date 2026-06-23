import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: ViewerModel
    @EnvironmentObject var canvas: CanvasController

    var body: some View {
        ZStack {
            Palette.backdrop.ignoresSafeArea()

            if model.isEmpty {
                EmptyStateView()
            } else {
                ImageCanvas(model: model, controller: canvas).ignoresSafeArea()
            }

            // Edge navigation chevrons.
            if !model.isEmpty, model.count > 1, model.chromeVisible {
                NavChevrons()
            }

            // Top toolbar + bottom filmstrip.
            VStack(spacing: 0) {
                if model.chromeVisible, !model.isEmpty {
                    ViewerToolbar()
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                if model.chromeVisible, model.filmstripVisible, model.count > 1 {
                    Filmstrip()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Info overlay, top-trailing under the toolbar.
            if model.infoVisible, let info = model.info {
                VStack {
                    HStack {
                        Spacer()
                        InfoOverlay(info: info)
                            .padding(.top, 60)
                            .padding(.trailing, 16)
                    }
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.chromeVisible)
        .animation(.easeInOut(duration: 0.18), value: model.filmstripVisible)
        .animation(.easeInOut(duration: 0.18), value: model.infoVisible)
        .background(WindowAccessor(title: model.currentName ?? "MacView"))
        .onOpenURL { url in model.open(url: url) }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .confirmationDialog(
            "Move “\(model.currentName ?? "")” to Trash?",
            isPresented: $model.showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { model.performDelete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else { return false }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            guard FolderScanner.isImage(url) else { return }
            DispatchQueue.main.async { model.open(url: url) }
        }
        return true
    }
}

/// Shown when no image is open (launched from the Dock, or after deleting the
/// last image in a folder).
struct EmptyStateView: View {
    @EnvironmentObject var model: ViewerModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.secondary)
            Text("No Image Open")
                .font(.title2.weight(.semibold))
            Text("Open an image (⌘O) or drop one here.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("Open…") { model.openWithPanel() }
                .controlSize(.large)
                .padding(.top, 4)
        }
    }
}
