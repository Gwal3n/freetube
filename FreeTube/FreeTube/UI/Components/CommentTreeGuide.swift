import SwiftUI

/// Vertical spine + L-elbow used beside nested comment avatars (YouTube-style reply tree).
@available(iOS 17.0, *)
struct CommentTreeGuide: View {
    /// One entry per ancestor column to the left of this row's elbow.
    /// `true` means a sibling continues below, so the spine runs through the full row height.
    let ancestorContinues: [Bool]
    /// When false, this row is the last sibling and the elbow's vertical stem stops at the avatar.
    let hasMoreSiblings: Bool
    var guideWidth: CGFloat = 14
    var avatarCenterY: CGFloat = 12
    var lineWidth: CGFloat = 1.5
    var color: Color = Color.secondary.opacity(0.35)

    private var depth: Int { ancestorContinues.count + 1 }

    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            let midX = { (column: Int) -> CGFloat in
                CGFloat(column) * guideWidth + guideWidth * 0.5
            }
            let elbowY = min(max(avatarCenterY, 0), size.height)

            for column in 0..<ancestorContinues.count {
                guard ancestorContinues[column] else { continue }
                var spine = Path()
                spine.move(to: CGPoint(x: midX(column), y: 0))
                spine.addLine(to: CGPoint(x: midX(column), y: size.height))
                context.stroke(spine, with: .color(color), style: stroke)
            }

            let elbowColumn = depth - 1
            let x = midX(elbowColumn)
            var elbow = Path()
            elbow.move(to: CGPoint(x: x, y: 0))
            elbow.addLine(to: CGPoint(x: x, y: elbowY))
            elbow.addLine(to: CGPoint(x: size.width, y: elbowY))
            context.stroke(elbow, with: .color(color), style: stroke)

            if hasMoreSiblings {
                var continuation = Path()
                continuation.move(to: CGPoint(x: x, y: elbowY))
                continuation.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(continuation, with: .color(color), style: stroke)
            }
        }
        .frame(width: guideWidth * CGFloat(max(depth, 1)))
        .accessibilityHidden(true)
    }
}
