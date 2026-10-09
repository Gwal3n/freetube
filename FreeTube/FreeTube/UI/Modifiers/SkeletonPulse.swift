import SwiftUI

/// A low-frequency opacity pulse for loading-only placeholders. It changes no geometry, respects
/// Reduce Motion, and pauses when the app is not active so hidden tabs do not keep animating.
@available(iOS 17.0, *)
struct SkeletonPulse: ViewModifier {
    let dimmedOpacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isDimmed = false

    init(dimmedOpacity: Double = 0.72) {
        self.dimmedOpacity = dimmedOpacity
    }

    func body(content: Content) -> some View {
        content
            .opacity(isDimmed ? dimmedOpacity : 1)
            .onAppear(perform: updatePulse)
            .onChange(of: reduceMotion) { _, _ in updatePulse() }
            .onChange(of: scenePhase) { _, _ in updatePulse() }
    }

    private func updatePulse() {
        guard !reduceMotion, scenePhase == .active else {
            isDimmed = false
            return
        }
        guard !isDimmed else { return }
        withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
            isDimmed = true
        }
    }
}
