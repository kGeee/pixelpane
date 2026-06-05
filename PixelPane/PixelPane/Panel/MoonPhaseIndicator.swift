import SwiftUI

/// Brand waiting indicator: a moon that continuously morphs through its
/// phases (full → waning → new → waxing → full). Used everywhere the app
/// shows an in-progress state.
struct MoonPhaseIndicator: View {
    var diameter: CGFloat = 16
    var color: Color = PixelPaneBrand.beige
    /// Seconds for one full phase cycle.
    var period: TimeInterval = 3.2

    var body: some View {
        TimelineView(.animation) { context in
            let cycle = (context.date.timeIntervalSinceReferenceDate / period)
                .truncatingRemainder(dividingBy: 1)
            ZStack {
                // Faint earthshine disc so the new-moon moment never vanishes.
                Circle()
                    .fill(color.opacity(0.18))
                MoonPhaseShape(cycle: cycle)
                    .fill(color)
            }
            .frame(width: diameter, height: diameter)
        }
        .accessibilityLabel("Working")
    }
}

/// The lit portion of a moon at a point in its cycle.
///
/// `cycle` 0 is full, 0.5 is new, 1 wraps back to full. The boundary is the
/// circle's right semicircle plus an elliptical terminator whose horizontal
/// semi-axis sweeps from +r (full) through 0 (quarter) to -r (new); the
/// second half of the cycle mirrors so the moon waxes on the opposite side.
struct MoonPhaseShape: Shape {
    var cycle: Double

    var animatableData: Double {
        get { cycle }
        set { cycle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let phase = cycle - cycle.rounded(.down)
        let waning = phase < 0.5
        // k ∈ [-1, 1]: terminator semi-axis as a fraction of the radius.
        let k = CGFloat(cos(2 * .pi * (waning ? phase : 1 - phase)))

        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)

        var path = Path()
        // Right semicircle: top → bottom through the right edge.
        path.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)

        // Terminator: half-ellipse from bottom back to top, x semi-axis k·r
        // (bulges left when k > 0, right when k < 0). Two cubic quarters.
        let kappa: CGFloat = 0.5523
        path.addCurve(
            to: CGPoint(x: c.x - k * r, y: c.y),
            control1: CGPoint(x: c.x - k * kappa * r, y: c.y + r),
            control2: CGPoint(x: c.x - k * r, y: c.y + kappa * r)
        )
        path.addCurve(
            to: CGPoint(x: c.x, y: c.y - r),
            control1: CGPoint(x: c.x - k * r, y: c.y - kappa * r),
            control2: CGPoint(x: c.x - k * kappa * r, y: c.y - r)
        )
        path.closeSubpath()

        guard !waning else { return path }
        // Waxing half: mirror so light grows from the other limb.
        return path.applying(
            CGAffineTransform(translationX: c.x, y: 0)
                .scaledBy(x: -1, y: 1)
                .translatedBy(x: -c.x, y: 0)
        )
    }
}
