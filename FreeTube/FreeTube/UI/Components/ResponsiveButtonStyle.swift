import SwiftUI

/// Quiet, immediate touch acknowledgement for content buttons that otherwise use a plain style.
struct ResponsiveButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.68 : 1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.995)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
