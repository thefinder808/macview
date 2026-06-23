import SwiftUI

/// Left/right navigation chevrons overlaid on the image edges, like the Windows
/// 11 viewer. These are **visual hints only** (`allowsHitTesting(false)`): an
/// embedded NSView swallows clicks that land on bare SwiftUI shapes over it, so
/// the actual edge-click navigation is handled in the canvas (`ViewerModel.handleClick`).
/// Dimmed at the ends where there's nowhere to go.
struct NavChevrons: View {
    @EnvironmentObject var model: ViewerModel

    var body: some View {
        HStack {
            chevron("chevron.left", enabled: model.hasPrevious)
            Spacer()
            chevron("chevron.right", enabled: model.hasNext)
        }
        .padding(.horizontal, 16)
        .allowsHitTesting(false)
    }

    private func chevron(_ symbol: String, enabled: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 46, height: 46)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.10)))
            .opacity(enabled ? 0.6 : 0.18)
    }
}
