import SwiftUI

/// Timer-face header shared by the authentication screens and the Timer tab.
///
/// Reusing the exact same visual language is what makes the lock read as a
/// legitimate timer configuration screen rather than a disguised PIN keypad
/// (§3, §9.2). It shows a static dial with hour/minute hands for the selected
/// duration plus the large digits.
struct DurationDialHeader: View {
    let hours: Int
    let minutes: Int
    var title: String
    var accessibilityHint: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Metrics.spacingL) {
            Text(title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textPrimary)

            dial
                .frame(width: 132, height: 132)

            digits
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityHint(Text(accessibilityHint ?? "Double tap to adjust the duration wheels below."))
        }
    }

    private var digits: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Metrics.spacingS) {
            Text(String(format: "%02d", hours))
                .font(Theme.Typography.display(56))
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
            Text("h")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textSecondary)
            Text(String(format: "%02d", minutes))
                .font(Theme.Typography.display(56))
                .foregroundStyle(Theme.Palette.textPrimary)
                .contentTransition(.numericText())
            Text("m")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: minutes)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hours)
        .accessibilityHidden(true) // parent element combines it
    }

    private var accessibilityLabel: String {
        if hours == 0 {
            return "\(minutes) minutes"
        }
        if minutes == 0 {
            return "\(hours) hours"
        }
        return "\(hours) hours \(minutes) minutes"
    }

    // MARK: Dial

    /// Static clock face whose minute hand points at the selected minutes and
    /// whose hour hand tracks the hour. Drawn with Canvas so there is no
    /// layout cost per tick.
    private var dial: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 6

            // Ring.
            var ring = Path()
            ring.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            context.stroke(ring, with: .color(Theme.Palette.stroke), lineWidth: 1.5)

            // Hour ticks: 12 marks so it reads as a clock, not a gauge.
            for index in 0..<12 {
                let angle = Angle.degrees(Double(index) * 30 - 90)
                let outer = CGPoint(
                    x: center.x + cos(angle.radians) * radius,
                    y: center.y + sin(angle.radians) * radius
                )
                let inner = CGPoint(
                    x: center.x + cos(angle.radians) * (radius - (index % 3 == 0 ? 10 : 6)),
                    y: center.y + sin(angle.radians) * (radius - (index % 3 == 0 ? 10 : 6))
                )
                var tick = Path()
                tick.move(to: outer)
                tick.addLine(to: inner)
                context.stroke(
                    tick,
                    with: .color(index % 3 == 0 ? Theme.Palette.textSecondary : Theme.Palette.stroke),
                    lineWidth: index % 3 == 0 ? 2 : 1
                )
            }

            // Swept arc from 12 o'clock to the minutes hand, the same idiom
            // the Timer tab uses for progress.
            let minuteFraction = Double(minutes) / 60.0
            if minuteFraction > 0 {
                let start = Angle.degrees(-90)
                let end = Angle.degrees(-90 + minuteFraction * 360)
                var arc = Path()
                arc.addArc(center: center, radius: radius - 14, startAngle: start, endAngle: end, clockwise: false)
                context.stroke(arc, with: .color(Theme.Palette.accent.opacity(0.85)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            // Minute hand.
            drawHand(
                in: &context,
                center: center,
                angle: Angle.degrees(-90 + minuteFraction * 360),
                length: radius - 18,
                width: 2.5,
                color: Theme.Palette.accent
            )

            // Hour hand (12-hour visual wrap; the digits carry the true value).
            let hourFraction = Double(hours % 12) / 12.0
            drawHand(
                in: &context,
                center: center,
                angle: Angle.degrees(-90 + hourFraction * 360),
                length: radius - 42,
                width: 3.5,
                color: Theme.Palette.textPrimary
            )

            // Hub.
            let hubRadius: CGFloat = 4
            let hub = Path(ellipseIn: CGRect(x: center.x - hubRadius, y: center.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2))
            context.fill(hub, with: .color(Theme.Palette.textPrimary))
        }
    }

    private func drawHand(
        in context: inout GraphicsContext,
        center: CGPoint,
        angle: Angle,
        length: CGFloat,
        width: CGFloat,
        color: Color
    ) {
        var hand = Path()
        hand.move(to: CGPoint(
            x: center.x - cos(angle.radians) * (length * 0.16),
            y: center.y - sin(angle.radians) * (length * 0.16)
        ))
        hand.addLine(to: CGPoint(
            x: center.x + cos(angle.radians) * length,
            y: center.y + sin(angle.radians) * length
        ))
        context.stroke(hand, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}
