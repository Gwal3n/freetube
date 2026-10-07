import SwiftUI

/// The visible, blurred edge of a stashed floating video. Its clear half widens the hit target
/// without drawing a separate button over the video slice.
@available(iOS 17.0, *)
struct FloatingMiniPlayerStashTab: View {
    @AppStorage("oledMiniPlayer") private var oledMiniPlayer = false

    let isLeading: Bool
    let height: CGFloat
    let onRestore: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize, CGSize) -> Void

    var body: some View {
        Image(systemName: isLeading ? "chevron.right" : "chevron.left")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 22, height: height)
            .frame(width: 44, height: height,
                alignment: isLeading ? .leading : .trailing)
            .background {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay {
                        Capsule()
                            .fill(.black.opacity(oledMiniPlayer ? 0.3 : 0.08))
                    }
                    .frame(width: 44, height: height)
                    .offset(x: isLeading ? -22 : 22)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onRestore)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { onDragChanged($0.translation) }
                    .onEnded {
                        onDragEnded($0.translation, $0.predictedEndTranslation)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Show floating video")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onRestore() }
    }
}
