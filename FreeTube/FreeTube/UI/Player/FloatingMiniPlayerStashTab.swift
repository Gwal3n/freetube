import SwiftUI

/// The small, reachable edge affordance for a floating video stashed off-screen.
@available(iOS 17.0, *)
struct FloatingMiniPlayerStashTab: View {
    @AppStorage("oledMiniPlayer") private var oledMiniPlayer = false

    let isLeading: Bool
    let onRestore: () -> Void

    var body: some View {
        Button(action: onRestore) {
            Image(systemName: isLeading ? "chevron.right" : "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 64)
                .background {
                    if oledMiniPlayer {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.black)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
                .frame(width: 44, height: 76, alignment: isLeading ? .leading : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show floating video")
        .simultaneousGesture(
            DragGesture(minimumDistance: 8)
                .onEnded { value in
                    let inwardDistance = isLeading
                        ? value.translation.width : -value.translation.width
                    if inwardDistance > 28
                        && abs(value.translation.width) > abs(value.translation.height) * 1.2 {
                        onRestore()
                    }
                }
        )
    }
}
