import SwiftUI
import AppKit

/// Bottom thumbnail strip of every image in the folder. Click to jump; the
/// current image is highlighted and auto-scrolled into view.
struct Filmstrip: View {
    @EnvironmentObject var model: ViewerModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // Lazy so only cells near the viewport exist — a plain HStack
                // materializes every cell up front, firing every thumbnail
                // `.task` and decoding the entire folder on open.
                // Cells are identified by URL (the ForEach id), and scrolling
                // targets that id. An explicit `.id(index)` here made a newly
                // opened folder reuse the previous folder's cells — its first
                // few thumbnails and the highlight stayed stale.
                LazyHStack(spacing: 8) {
                    ForEach(Array(model.urls.enumerated()), id: \.element) { index, url in
                        ThumbnailCell(url: url,
                                      isCurrent: index == model.index,
                                      thumbnailer: model.thumbnailer)
                            .onTapGesture { model.jump(to: index) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(height: 84)
            .background(.ultraThinMaterial)
            .onChange(of: model.current) { _, url in
                guard let url else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(url, anchor: .center) }
            }
            .onAppear { if let url = model.current { proxy.scrollTo(url, anchor: .center) } }
        }
    }
}

private struct ThumbnailCell: View {
    let url: URL
    let isCurrent: Bool
    let thumbnailer: Thumbnailer
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.white.opacity(0.06))
            }
        }
        .frame(width: 84, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(isCurrent ? Palette.accent : .white.opacity(0.12),
                              lineWidth: isCurrent ? 2 : 1)
        )
        .contentShape(Rectangle())
        .task(id: url) { image = await thumbnailer.thumbnail(for: url) }
    }
}
