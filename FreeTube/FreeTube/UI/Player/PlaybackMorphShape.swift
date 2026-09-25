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
        var path = Path()

        addPolygon(
            from: [(0.12, 0.05), (0.48, 0.25), (0.48, 0.75), (0.12, 0.95)],
            to: [(0.18, 0.08), (0.38, 0.08), (0.38, 0.92), (0.18, 0.92)],
            amount: amount,
            in: rect,
            to: &path
        )
        addPolygon(
            from: [(0.48, 0.25), (0.92, 0.50), (0.92, 0.50), (0.48, 0.75)],
            to: [(0.62, 0.08), (0.82, 0.08), (0.82, 0.92), (0.62, 0.92)],
            amount: amount,
            in: rect,
            to: &path
        )
        return path
    }

    private func addPolygon(
        from start: [(CGFloat, CGFloat)],
        to end: [(CGFloat, CGFloat)],
        amount: CGFloat,
        in rect: CGRect,
        to path: inout Path
    ) {
        for index in start.indices {
            let x = start[index].0 + (end[index].0 - start[index].0) * amount
            let y = start[index].1 + (end[index].1 - start[index].1) * amount
            let point = CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            if index == start.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
    }
}
