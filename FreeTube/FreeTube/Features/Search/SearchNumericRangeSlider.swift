import SwiftUI

/// Dual-thumb track used by `SearchNumericRangeSheet`. Positions are normalized `0...1`; the
/// leading thumb is the lower bound and the trailing thumb is the upper bound.
@available(iOS 17.0, *)
struct SearchNumericRangeSlider: View {
    private enum Thumb {
        case lower, upper
    }

    @Binding var lower: Double
    @Binding var upper: Double

    var lowerAccessibilityValue: String
    var upperAccessibilityValue: String

    @State private var activeThumb: Thumb?
    @State private var trackWidth: CGFloat = 0

    private let thumbDiameter: CGFloat = 28
    private let trackHeight: CGFloat = 4

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: trackHeight)

            Capsule()
                .fill(Color.accentColor)
                .frame(width: max(0, (upper - lower) * trackWidth), height: trackHeight)
                .offset(x: lower * trackWidth)

            thumb(highlighted: activeThumb == .lower)
                .offset(x: lower * trackWidth - thumbDiameter / 2)
                .accessibilityLabel("Minimum")
                .accessibilityValue(lowerAccessibilityValue)

            thumb(highlighted: activeThumb == .upper)
                .offset(x: upper * trackWidth - thumbDiameter / 2)
                .accessibilityLabel("Maximum")
                .accessibilityValue(upperAccessibilityValue)
        }
        .frame(height: thumbDiameter)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { trackWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in trackWidth = width }
            }
        }
        .contentShape(Rectangle())
        .gesture(trackDrag)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private var trackDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard trackWidth > 0 else { return }
                if activeThumb == nil {
                    activeThumb = nearestThumb(to: value.startLocation.x)
                }
                let position = min(1, max(0, value.location.x / trackWidth))
                switch activeThumb {
                case .lower:
                    lower = min(position, upper)
                case .upper:
                    upper = max(position, lower)
                case .none:
                    break
                }
            }
            .onEnded { _ in
                activeThumb = nil
            }
    }

    private func thumb(highlighted: Bool) -> some View {
        Circle()
            .fill(Color(.systemBackground))
            .frame(width: thumbDiameter, height: thumbDiameter)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .overlay {
                Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
            .scaleEffect(highlighted ? 1.08 : 1)
            .allowsHitTesting(false)
    }

    private func nearestThumb(to x: CGFloat) -> Thumb {
        let lowerX = lower * trackWidth
        let upperX = upper * trackWidth
        // Prefer the upper thumb when they overlap so Unlimited stays reachable from a shared point.
        if abs(x - lowerX) == abs(x - upperX) { return .upper }
        return abs(x - lowerX) < abs(x - upperX) ? .lower : .upper
    }
}
