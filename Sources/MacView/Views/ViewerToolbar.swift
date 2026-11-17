import SwiftUI
import AppKit

/// The floating top toolbar: position counter + filename on the left, then zoom,
/// rotate, info, delete, and fullscreen controls in a single material capsule.
struct ViewerToolbar: View {
    @EnvironmentObject var model: ViewerModel
    @EnvironmentObject var canvas: CanvasController

    var body: some View {
        HStack(spacing: 10) {
            if model.count > 0 {
                Text("\(model.index + 1) of \(model.count)")
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let name = model.currentName {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 200)
            }

            divider
            icon("minus.magnifyingglass", "Zoom Out (⌘−)") { canvas.zoomOut() }
            // verbatim: a localized interpolation adds a grouping separator
            // ("4,000%"), which wraps in this fixed-width slot.
            Text(verbatim: "\(canvas.zoomPercent)%")
                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.secondary).frame(width: 46)
            icon("plus.magnifyingglass", "Zoom In (⌘+)") { canvas.zoomIn() }
            icon("aspectratio", "Zoom to Fit (⌘0)") { canvas.fit() }
            icon("1.magnifyingglass", "Actual Size (⌘1)") { canvas.actualSize() }

            divider
            icon("rotate.left", "Rotate Left (⌘L)") { model.rotateLeft() }.disabled(model.isEmpty)
            icon("rotate.right", "Rotate Right (⌘R)") { model.rotateRight() }.disabled(model.isEmpty)

            divider
            icon("info.circle", "Info (⌘I)", active: model.infoVisible) { model.toggleInfo() }
            if let url = model.current {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Share")
            }
            icon("trash", "Move to Trash (⌫)") { model.requestDelete() }.disabled(model.isEmpty)
            icon("arrow.up.left.and.arrow.down.right", "Full Screen (⌃⌘F)") { toggleFullScreen() }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 16)
    }

    private func icon(_ symbol: String, _ help: String, active: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 26, height: 26)
                .background(active ? Palette.accent.opacity(0.30) : .clear, in: Circle())
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.primary))
        .help(help)
    }

    private func toggleFullScreen() {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }
}
