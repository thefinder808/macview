import SwiftUI
import AppKit

/// Bottom thumbnail strip of every image in the folder. Click to jump; the
/// current image is highlighted and auto-scrolled into view.
struct Filmstrip: View {
    @EnvironmentObject var model: ViewerModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(model.urls.enumerated()), id: \.element) { index, url in
                        ThumbnailCell(url: url,
                                      isCurrent: index == model.index,
                                      thumbnailer: model.thumbnailer)
                            .id(index)
                            .onTapGesture { model.jump(to: index) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(height: 84)
            .background(.ultraThinMaterial)
            .onChange(of: model.index) { _, newValue in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(newValue, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(model.index, anchor: .center) }
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
