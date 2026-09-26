import SwiftUI

/// Fullscreen-only direct manipulation of media, not transport chrome. Live pinches have no
/// interpolation; release gently settles near fit/fill, with one selection tick at each detent.
@available(iOS 17.0, *)
struct PlayerZoomModifier: ViewModifier {
    let isEnabled: Bool
    let videoID: String?
    let presentationSize: CGSize
    let viewportSize: CGSize
    let topInset: CGFloat
    let onInteractionChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPinching = false
    @State private var baseScale: CGFloat = 1
    @State private var liveScale: CGFloat = 1
    @State private var showsFeedback = false
    @State private var lastDetent: Int? = 1
    @State private var feedbackTrigger = 0

    private var fillScale: CGFloat {
        PlayerZoomGeometry.fillScale(video: presentationSize, viewport: viewportSize)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isEnabled ? liveScale : 1)
            .frame(width: viewportSize.width, height: viewportSize.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(pinch, including: isEnabled ? .all : .subviews)
            .overlay(alignment: .top) {
                if isEnabled, showsFeedback {
                    Text(verbatim: Double(liveScale).formatted(.number.precision(.fractionLength(1))) + "×")
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
            .sensoryFeedback(.selection, trigger: feedbackTrigger)
            .onChange(of: isPinching) { _, active in
                onInteractionChanged(active && isEnabled)
                // GestureState also resets on cancellation (rotation, dismissal, interruptions).
                if !active { settle() }
            }
            .task(id: isPinching) {
                guard !isPinching else { return }
                do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                    showsFeedback = false
                }
            }
            .onChange(of: isEnabled) { _, _ in reset() }
            .onChange(of: videoID) { _, _ in reset() }
            .onChange(of: viewportSize) { _, _ in reset() }
    }

    private var pinch: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.005)
            .updating($isPinching) { _, active, transaction in
                active = true
                transaction.disablesAnimations = true
            }
            .onChanged { value in
                guard isEnabled else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    liveScale = PlayerZoomGeometry.clamped(baseScale * value.magnification, fillScale: fillScale)
                    showsFeedback = true
                }
                let detent: Int? = abs(liveScale - 1) < 0.035 ? 1
                    : fillScale > 1.08 && abs(liveScale - fillScale) / fillScale < 0.025 ? 2 : nil
                // Keep the last actual detent, not the surrounding tolerance band: finger
                // jitter at its edge must not produce repeated ticks or vibration.
                if let detent, detent != lastDetent {
                    feedbackTrigger += 1
                    lastDetent = detent
                }
            }
            .onEnded { _ in settle() }
    }

    private func settle() {
        guard isEnabled else { return }
        let target = PlayerZoomGeometry.settled(liveScale, fillScale: fillScale)
        baseScale = target
        withAnimation(reduceMotion ? nil : .spring(duration: 0.24, bounce: 0)) {
            liveScale = target
        }
    }

    private func reset() {
        onInteractionChanged(false)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            baseScale = 1
            liveScale = 1
            showsFeedback = false
            lastDetent = 1
        }
    }
}
