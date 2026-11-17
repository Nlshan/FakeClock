import SwiftUI

/// Central design tokens for Timer Lock. Every screen draws from these values
/// so the application reads as one system: near-black background, charcoal
/// surfaces, white primary text, muted grey secondary text, a single blue
/// accent, and restrained success/error colors.
enum Theme {

    // MARK: Palette

    /// Appearance-aware colors. Dark values are the designed-first palette;
    /// light values keep contrast targets in light mode.
    enum Palette {
        static let background = Color(uiColor: .themed(darkHex: 0x0A0A0C, lightHex: 0xF4F5F7))
        static let surface = Color(uiColor: .themed(darkHex: 0x15161A, lightHex: 0xFFFFFF))
        static let surfaceElevated = Color(uiColor: .themed(darkHex: 0x1E2026, lightHex: 0xE9EBF0))
        static let stroke = Color(uiColor: .themed(darkHex: 0x2A2D35, lightHex: 0xD6D9E0))
        static let textPrimary = Color(uiColor: .themed(darkHex: 0xF4F5F7, lightHex: 0x15161A))
        static let textSecondary = Color(uiColor: .themed(darkHex: 0x9BA1AD, lightHex: 0x5B616E))
        static let accent = Color(uiColor: .themed(darkHex: 0x4A9EFF, lightHex: 0x1F6FDB))
        static let success = Color(uiColor: .themed(darkHex: 0x4CCC7F, lightHex: 0x1E8E4C))
        static let danger = Color(uiColor: .themed(darkHex: 0xFF6B6B, lightHex: 0xC93A3A))
        static let warning = Color(uiColor: .themed(darkHex: 0xFFB340, lightHex: 0xB06E10))
    }

    // MARK: Metrics

    enum Metrics {
        // Spacing scale.
        static let spacingXS: CGFloat = 4
        static let spacingS: CGFloat = 8
        static let spacingM: CGFloat = 12
        static let spacingL: CGFloat = 16
        static let spacingXL: CGFloat = 24
        static let spacingXXL: CGFloat = 32

        // Corner radii.
        static let cornerS: CGFloat = 8
        static let cornerM: CGFloat = 12
        static let cornerL: CGFloat = 16
        static let cornerXL: CGFloat = 22

        // Touch targets.
        static let minimumTouchTarget: CGFloat = 44

        // Stroke widths.
        static let hairline: CGFloat = 0.5
        static let separator: CGFloat = 1
    }

    // MARK: Typography

    enum Typography {
        /// Large monospaced-digit display used by clock faces and countdowns.
        static func display(_ size: CGFloat) -> Font {
            .system(size: size, weight: .regular, design: .rounded).monospacedDigit()
        }

        static let title = Font.system(.title2, design: .rounded).weight(.bold)
        static let headline = Font.system(.headline)
        static let body = Font.system(.body)
        static let callout = Font.system(.callout)
        static let subheadline = Font.system(.subheadline)
        static let caption = Font.system(.caption)
        static let captionStrong = Font.system(.caption).weight(.semibold)
    }
}
