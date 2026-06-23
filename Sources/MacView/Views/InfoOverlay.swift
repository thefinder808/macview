import SwiftUI
import Foundation

/// Corner panel showing the current image's dimensions, size, type, and any
/// available EXIF — toggled with the info button or ⌘I.
struct InfoOverlay: View {
    let info: ImageInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(info.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1).truncationMode(.middle)
            row("Dimensions", dimensions)
            row("Size", sizeString)
            row("Type", info.typeDescription)
            row("Taken", info.dateTaken)
            row("Camera", info.camera)
            row("Lens", info.lens)
            row("Exposure", info.exposure)
        }
        .padding(14)
        .frame(width: 264, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
    }

    private var dimensions: String? {
        guard let w = info.pixelWidth, let h = info.pixelHeight else { return nil }
        return "\(w) × \(h)"
    }

    private var sizeString: String? {
        guard let size = info.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }
}
