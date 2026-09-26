import SwiftUI

/// Renders the fullscreen media transform; native recognition remains with the AVPlayer bridge
/// so pinch/pan and two-finger play/pause have explicit, deterministic failure dependencies.
@available(iOS 17.0, *)
struct PlayerZoomModifier: ViewModifier {
    let model: PlayerZoomModel
    let isEnabled: Bool
    let videoID: String?
    let presentationSize: CGSize
    let viewportSize: CGSize
    let topInset: CGFloat
    let onInteractionChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsFeedback = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isEnabled ? model.scale : 1)
            .offset(isEnabled ? model.offset : .zero)
            .frame(width: viewportSize.width, height: viewportSize.height)
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if isEnabled, showsFeedback {
                    Text(verbatim: Double(model.scale).formatted(.number.precision(.fractionLength(1))) + "×")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, topInset + 14)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .sensoryFeedback(.selection, trigger: model.feedbackTrigger)
            .onChange(of: model.isInteracting) { _, active in
                onInteractionChanged(active && isEnabled)
                if active { showsFeedback = true }
            }
            .task(id: model.isInteracting) {
                guard !model.isInteracting else { return }
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                    showsFeedback = false
                }
            }
            .onChange(of: isEnabled, initial: true) { _, _ in reset() }
            .onChange(of: videoID) { _, _ in reset() }
            .onChange(of: viewportSize) { _, _ in reset() }
            .onChange(of: presentationSize) { _, _ in reset() }
            .onChange(of: reduceMotion) { _, _ in configure() }
    }

    private func reset() {
        onInteractionChanged(false)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.reset()
            showsFeedback = false
        }
        configure()
    }

    private func configure() {
        model.configure(video: presentationSize, viewport: viewportSize, reduceMotion: reduceMotion)
    }
}
