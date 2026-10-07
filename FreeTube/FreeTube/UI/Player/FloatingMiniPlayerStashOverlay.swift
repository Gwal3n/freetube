import SwiftUI

/// A material cover with the exact bounds and corner shape of the floating video. While the
/// video is mostly off-screen, only the covered edge and its subtle restore chevron remain visible.
@available(iOS 17.0, *)
struct FloatingMiniPlayerStashOverlay: View {
    @AppStorage("oledMiniPlayer") private var oledMiniPlayer = false

    let isLeading: Bool
    let size: CGSize

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: FloatingMiniPlayerChrome.cornerRadius,
            style: .continuous
        )

        shape
            .fill(.regularMaterial)
            .overlay {
                shape.fill(.black.opacity(oledMiniPlayer ? 0.3 : 0.08))
            }
            .overlay(alignment: isLeading ? .trailing : .leading) {
                Image(systemName: isLeading ? "chevron.right" : "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 22, height: size.height)
            }
            .clipShape(shape)
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
}
