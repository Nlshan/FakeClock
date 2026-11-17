import SwiftUI

/// Filled accent button used for primary actions (Start, Unlock, Save).
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Metrics.minimumTouchTarget + 8)
            .padding(.vertical, Theme.Metrics.spacingM)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cornerL, style: .continuous)
                    .fill(color)
                    .opacity(configuration.isPressed ? 0.75 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Outlined button used for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = Theme.Palette.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.Metrics.minimumTouchTarget + 8)
            .padding(.vertical, Theme.Metrics.spacingM)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.cornerL, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.18 : 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Metrics.cornerL, style: .continuous)
                    .strokeBorder(color.opacity(0.45), lineWidth: Theme.Metrics.separator)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Large circular button used by the stopwatch and timer controls.
struct CircularButtonStyle: ButtonStyle {
    enum Role {
        case positive
        case neutral
        case negative

        var fill: Color {
            switch self {
            case .positive: return Theme.Palette.success.opacity(0.16)
            case .neutral: return Theme.Palette.surfaceElevated
            case .negative: return Theme.Palette.danger.opacity(0.16)
            }
        }

        var stroke: Color {
            switch self {
            case .positive: return Theme.Palette.success.opacity(0.6)
            case .neutral: return Theme.Palette.stroke
            case .negative: return Theme.Palette.danger.opacity(0.6)
            }
        }

        var foreground: Color {
            switch self {
            case .positive: return Theme.Palette.success
            case .neutral: return Theme.Palette.textPrimary
            case .negative: return Theme.Palette.danger
            }
        }
    }

    var role: Role
    var diameter: CGFloat = 72

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.subheadline.weight(.semibold))
            .foregroundStyle(role.foreground)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(role.fill))
            .overlay(Circle().strokeBorder(role.stroke, lineWidth: Theme.Metrics.separator))
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .accessibilityAddTraits(.isButton)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var tlPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var tlSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
