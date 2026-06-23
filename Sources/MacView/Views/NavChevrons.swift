import SwiftUI

/// Left/right navigation chevrons overlaid on the image edges, like the Windows
/// 11 viewer. Dim until hovered; disabled (and nearly invisible) at the ends.
struct NavChevrons: View {
    @EnvironmentObject var model: ViewerModel
    @State private var hoverLeft = false
    @State private var hoverRight = false

    var body: some View {
        HStack {
            chevron("chevron.left", enabled: model.hasPrevious, hovering: hoverLeft) {
                model.previous()
            }
            .onHover { hoverLeft = $0 }
            .opacity(opacity(enabled: model.hasPrevious, hovering: hoverLeft))
            .animation(.easeOut(duration: 0.15), value: hoverLeft)

            Spacer()

            chevron("chevron.right", enabled: model.hasNext, hovering: hoverRight) {
                model.next()
            }
            .onHover { hoverRight = $0 }
            .opacity(opacity(enabled: model.hasNext, hovering: hoverRight))
            .animation(.easeOut(duration: 0.15), value: hoverRight)
        }
        .padding(.horizontal, 16)
    }

    private func opacity(enabled: Bool, hovering: Bool) -> Double {
        guard enabled else { return 0.15 }
        return hovering ? 1.0 : 0.5
    }

    private func chevron(_ symbol: String, enabled: Bool, hovering: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.10)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(!enabled)
    }
}
