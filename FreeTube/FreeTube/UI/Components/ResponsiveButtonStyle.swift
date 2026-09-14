import SwiftUI

/// Quiet, immediate touch acknowledgement for content buttons that otherwise use a plain style.
struct ResponsiveButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Keep acknowledgement visible without the bright/dark flash produced by the old
            // 32% opacity drop. Touch-down is deliberately quicker than release: the interface
            // answers the finger immediately, then settles without snapping back.
            .opacity(configuration.isPressed ? 0.84 : 1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.985)
            .animation(
                reduceMotion
                    ? nil
                    : (configuration.isPressed
                        ? .easeOut(duration: 0.07)
                        : .smooth(duration: 0.16)),
                value: configuration.isPressed
            )
    }
}
