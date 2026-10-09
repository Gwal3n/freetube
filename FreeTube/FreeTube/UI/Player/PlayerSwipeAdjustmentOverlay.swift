import SwiftUI

/// Compact side HUD for a one-finger brightness or player-volume adjustment.
@available(iOS 17.0, *)
struct PlayerSwipeAdjustmentOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let model: PlayerSwipeAdjustmentModel
    let surfaceSize: CGSize

    var body: some View {
        Group {
            if let kind = model.kind {
                VStack(spacing: 8) {
                    Image(systemName: kind == .brightness ? "sun.max.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .medium))

                    Capsule()
                        .fill(.white.opacity(0.24))
                        .frame(width: 4, height: 62)
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(.white)
                                .frame(width: 4, height: 62 * model.level)
                        }

                    Text("\(Int((model.level * 100).rounded()))%")
                        .font(.caption2.monospacedDigit().weight(.medium))
                }
                .foregroundStyle(.white)
                .frame(width: 48, height: 126)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .position(
                    x: kind == .brightness ? 34 : max(34, surfaceSize.width - 34),
                    y: surfaceSize.height / 2
                )
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.kind)
        .allowsHitTesting(false)
    }
}
