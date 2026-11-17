import SwiftUI
import UIKit

// MARK: - Color hex helpers

extension Color {
    /// Creates a color from a 24-bit RGB hex value in the sRGB color space.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}

extension UIColor {
    /// Returns a dynamic color that resolves differently for light and dark
    /// user-interface styles, so the same token works under every appearance.
    static func themed(darkHex: UInt32, lightHex: UInt32) -> UIColor {
        UIColor(dynamicProvider: { traits in
            switch traits.userInterfaceStyle {
            case .dark:
                return UIColor(hex: darkHex)
            default:
                return UIColor(hex: lightHex)
            }
        })
    }

    /// Creates a color from a 24-bit RGB hex value.
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
