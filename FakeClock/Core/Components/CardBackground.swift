import SwiftUI

/// Standard card treatment used across the app: elevated surface fill,
/// consistent corner radius, and a hairline border.
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.Metrics.cornerL

    func body(content: Content) -> some View {
        content
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.Palette.stroke, lineWidth: Theme.Metrics.hairline)
            )
    }
}

extension View {
    func cardStyle(cornerRadius: CGFloat = Theme.Metrics.cornerL) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}
