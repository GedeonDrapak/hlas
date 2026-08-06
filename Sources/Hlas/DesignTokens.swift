import SwiftUI

/// Hlas design tokens - fusion of the Fakturio premium neutral system
/// (Linear/Raycast near-black surfaces, hairline borders) and the
/// Eden Makers system (bio-digital green accent, uppercase tracked labels).
/// Rule from both systems: never pure black, never pure white.
enum DS {
    // Surfaces (dark-first)
    static let bg = Color(hex: 0x0C0D0F)          // near-black neutral page
    static let surface = Color(hex: 0x161719)     // elevated panel
    static let surfaceHover = Color(hex: 0x1E2023)

    // Text
    static let fg = Color(white: 0.93)            // soft off-white
    static let fg2 = Color(white: 0.62)           // muted
    static let fg3 = Color(white: 0.52)           // tertiary, AA contrast on bg

    // Accent - Eden bio-digital green
    static let brand = Color(hue: 153 / 360, saturation: 1.0, brightness: 0.90)
    static let destructive = Color(hue: 0, saturation: 0.72, brightness: 0.86)

    // Hairlines
    static let border = Color.white.opacity(0.08)
    static let borderSubtle = Color.white.opacity(0.06)

    // Shape
    static let radius: CGFloat = 16
    static let radiusSm: CGFloat = 8

    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let family: String
        switch weight {
        case .bold, .heavy, .black: family = "Satoshi-Bold"
        case .medium, .semibold: family = "Satoshi-Medium"
        default: family = "Satoshi-Regular"
        }
        let style: Font.TextStyle
        switch size {
        case 20...: style = .title2
        case 16...: style = .headline
        case ..<12: style = .caption
        default: style = .body
        }
        return .custom(family, size: size, relativeTo: style)
    }

    static func label(_ size: CGFloat = 11) -> Font {
        .custom("Satoshi-Medium", size: size, relativeTo: .caption).monospacedDigit()
    }

    /// Konect Demo — display font for brand moments (wordmark, pure-letter
    /// uppercase labels ONLY: the demo has 52 glyphs, no digits/punctuation).
    /// License: free for personal use; buy from Ragam Kata before any public
    /// distribution (see docs/HANDOFF.md).
    static func display(_ size: CGFloat) -> Font {
        .custom("KonectDemo-Regular", size: size, relativeTo: .title)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
