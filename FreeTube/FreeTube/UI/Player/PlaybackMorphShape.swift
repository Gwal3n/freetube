import SwiftUI

/// A play triangle split into two pieces that become pause bars without shrinking the glyph.
/// Keeping both states in one animatable path avoids SF Symbol replacement's scale-down phase.
@available(iOS 17.0, *)
struct PlaybackMorphShape: Shape {
    /// 0 is play; 1 is pause.
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let amount = min(1, max(0, progress))
        let cornerRadius = min(rect.width, rect.height) * 0.04
        var path = Path()

        addPolygon(
            from: [(0.12, 0.05), (0.48, 0.25), (0.48, 0.75), (0.12, 0.95)],
            to: [(0.18, 0.08), (0.38, 0.08), (0.38, 0.92), (0.18, 0.92)],
            amount: amount,
            cornerRadii: [cornerRadius, cornerRadius * amount, cornerRadius * amount, cornerRadius],
            in: rect,
            to: &path
        )
        addPolygon(
            from: [(0.48, 0.25), (0.92, 0.50), (0.92, 0.50), (0.48, 0.75)],
            to: [(0.62, 0.08), (0.82, 0.08), (0.82, 0.92), (0.62, 0.92)],
            amount: amount,
            cornerRadii: [cornerRadius * amount, cornerRadius, cornerRadius, cornerRadius * amount],
            in: rect,
            to: &path
        )
        return path
    }

    private func addPolygon(
        from start: [(CGFloat, CGFloat)],
        to end: [(CGFloat, CGFloat)],
        amount: CGFloat,
        cornerRadii: [CGFloat],
        in rect: CGRect,
        to path: inout Path
    ) {
        let points = start.indices.map { index in
            let x = start[index].0 + (end[index].0 - start[index].0) * amount
            let y = start[index].1 + (end[index].1 - start[index].1) * amount
            return CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        for index in points.indices {
            let previous = points[(index + points.count - 1) % points.count]
            let point = points[index]
            let next = points[(index + 1) % points.count]
            let incoming = (
                (point.x - previous.x) * (point.x - previous.x)
                + (point.y - previous.y) * (point.y - previous.y)
            ).squareRoot()
            let outgoing = (
                (next.x - point.x) * (next.x - point.x)
                + (next.y - point.y) * (next.y - point.y)
            ).squareRoot()
            let radius = min(cornerRadii[index], min(incoming * 0.35, outgoing * 0.35))
            let before = incoming > 0
                ? CGPoint(
                    x: point.x + (previous.x - point.x) * radius / incoming,
                    y: point.y + (previous.y - point.y) * radius / incoming
                )
                : point
            let after = outgoing > 0
                ? CGPoint(
                    x: point.x + (next.x - point.x) * radius / outgoing,
                    y: point.y + (next.y - point.y) * radius / outgoing
                )
                : point
            if index == start.startIndex {
                path.move(to: before)
            } else {
                path.addLine(to: before)
            }
            path.addQuadCurve(to: after, control: point)
        }
        path.closeSubpath()
    }
}
