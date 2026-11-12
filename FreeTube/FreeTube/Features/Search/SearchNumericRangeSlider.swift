import SwiftUI

/// Dual-thumb track used by `SearchNumericRangeSheet`, styled after the system `UISlider`.
/// Values are stop indices in `0...maxIndex`; the leading thumb is the lower bound and the
/// trailing thumb the upper bound. Width is read from the enclosing `GeometryReader` rather than
/// from the track's own content so a transient out-of-range value can never widen the layout.
@available(iOS 17.0, *)
struct SearchNumericRangeSlider: View {
    private enum Thumb {
        case lower, upper
    }

    @Binding var lower: Int
    @Binding var upper: Int
    let maxIndex: Int

    var lowerAccessibilityValue: String
    var upperAccessibilityValue: String

    @State private var activeThumb: Thumb?

    private let thumbDiameter: CGFloat = 27
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let usableWidth = max(1, proxy.size.width - thumbDiameter)
            let lowerX = offset(for: lower, usableWidth: usableWidth)
            let upperX = offset(for: upper, usableWidth: usableWidth)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemFill))
                    .frame(width: usableWidth, height: trackHeight)
                    .offset(x: thumbDiameter / 2)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, upperX - lowerX), height: trackHeight)
                    .offset(x: thumbDiameter / 2 + lowerX)

                thumb
                    .offset(x: lowerX)
                    .accessibilityElement()
                    .accessibilityLabel("Minimum")
                    .accessibilityValue(lowerAccessibilityValue)
                    .accessibilityAdjustableAction { direction in
                        adjust(.lower, direction: direction)
                    }

                thumb
                    .offset(x: upperX)
                    .accessibilityElement()
                    .accessibilityLabel("Maximum")
                    .accessibilityValue(upperAccessibilityValue)
                    .accessibilityAdjustableAction { direction in
                        adjust(.upper, direction: direction)
                    }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(trackDrag(usableWidth: usableWidth))
        }
        .frame(height: thumbDiameter + 10)
        .transaction { $0.animation = nil }
        .sensoryFeedback(.selection, trigger: lower)
        .sensoryFeedback(.selection, trigger: upper)
    }

    private func offset(for index: Int, usableWidth: CGFloat) -> CGFloat {
        guard maxIndex > 0 else { return 0 }
        let clamped = min(max(index, 0), maxIndex)
        return CGFloat(clamped) / CGFloat(maxIndex) * usableWidth
    }

    private func index(at x: CGFloat, usableWidth: CGFloat) -> Int {
        let fraction = min(1, max(0, (x - thumbDiameter / 2) / usableWidth))
        return Int((fraction * CGFloat(maxIndex)).rounded())
    }

    private func trackDrag(usableWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if activeThumb == nil {
                    activeThumb = chooseThumb(for: value, usableWidth: usableWidth)
                }
                let target = index(at: value.location.x, usableWidth: usableWidth)
                switch activeThumb {
                case .lower:
                    let next = min(target, upper)
                    if next != lower { lower = next }
                case .upper:
                    let next = max(target, lower)
                    if next != upper { upper = next }
                case .none:
                    break
                }
            }
            .onEnded { _ in
                activeThumb = nil
            }
    }

    /// Picks the nearer thumb. When both share a stop, the drag direction decides so either end
    /// can be pulled apart; no choice is made until the finger has moved.
    private func chooseThumb(for value: DragGesture.Value, usableWidth: CGFloat) -> Thumb? {
        let x = value.startLocation.x - thumbDiameter / 2
        let lowerDistance = abs(x - offset(for: lower, usableWidth: usableWidth))
        let upperDistance = abs(x - offset(for: upper, usableWidth: usableWidth))
        if lower == upper {
            let dx = value.translation.width
            guard abs(dx) > 2 else { return nil }
            return dx < 0 ? .lower : .upper
        }
        return lowerDistance <= upperDistance ? .lower : .upper
    }

    private func adjust(_ thumb: Thumb, direction: AccessibilityAdjustmentDirection) {
        let step: Int
        switch direction {
        case .increment: step = 1
        case .decrement: step = -1
        @unknown default: return
        }
        switch thumb {
        case .lower: lower = min(max(0, lower + step), upper)
        case .upper: upper = max(min(maxIndex, upper + step), lower)
        }
    }

    private var thumb: some View {
        Circle()
            .fill(.white)
            .frame(width: thumbDiameter, height: thumbDiameter)
            .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
            .allowsHitTesting(false)
    }
}
