import SwiftUI

/// Small pill used for labels such as "GMT+5:30", "OFF", "Day", or "Night".
/// State is always paired with text so color alone never carries meaning.
struct StatusBadge: View {
    enum Tone {
        case neutral
        case accent
        case success
        case danger
        case warning

        var foreground: Color {
            switch self {
            case .neutral: return Theme.Palette.textSecondary
            case .accent: return Theme.Palette.accent
            case .success: return Theme.Palette.success
            case .danger: return Theme.Palette.danger
            case .warning: return Theme.Palette.warning
            }
        }

        var background: Color { foreground.opacity(0.14) }
    }

    let text: String
    var systemImage: String? = nil
    var tone: Tone = .neutral

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(Theme.Typography.captionStrong)
        }
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, Theme.Metrics.spacingS)
        .padding(.vertical, 3)
        .background(Capsule().fill(tone.background))
        .accessibilityElement(children: .combine)
    }
}
