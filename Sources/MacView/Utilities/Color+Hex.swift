import SwiftUI

// Hex color helper — the fleet convention (no xcassets). Lets views spell
// accent/background colors as hex literals.
extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

/// Central palette for MacView's dark viewer chrome.
enum Palette {
    /// Near-black canvas backdrop the image floats on.
    static let backdrop = Color(hex: 0x101012)
    /// Accent used for the current-image highlight and active controls.
    static let accent = Color(hex: 0x3A86FF)
}
