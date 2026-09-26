import SwiftUI

/// A small, interruptible settling motion on the lightweight chrome only. It never transforms
/// the AVPlayer host or changes the container's finger-tracking and dismissal decisions.
@available(iOS 17.0, *)
struct MiniPlayerArrivalModifier: ViewModifier {
    let isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrival: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion ? 1 : 0.975 + 0.025 * arrival, anchor: .bottom)
            .offset(y: reduceMotion ? 0 : 6 * (1 - arrival))
            .onAppear {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { arrival = isExpanded ? 0 : 1 }
            }
            .onChange(of: isExpanded) { _, expanded in
                if expanded {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { arrival = 0 }
                } else {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.44, bounce: 0.18)) {
                        arrival = 1
                    }
                }
            }
    }
}
