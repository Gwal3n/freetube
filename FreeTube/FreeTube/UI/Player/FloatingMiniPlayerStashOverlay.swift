import SwiftUI

/// A material cover matching the floating video's shape, with a one-pixel bleed to conceal
/// antialiased seams. Only its edge and restore chevron remain visible while stashed.
@available(iOS 17.0, *)
struct FloatingMiniPlayerStashOverlay: View {
    @Environment(\.displayScale) private var displayScale

    let isLeading: Bool
    let size: CGSize

    var body: some View {
        let bleed = 1 / max(displayScale, 1)
        let shape = RoundedRectangle(
            cornerRadius: FloatingMiniPlayerChrome.cornerRadius + bleed,
            style: .continuous
        )

        shape
            .fill(.regularMaterial)
            .overlay {
                shape.fill(.black.opacity(0.3))
            }
            .overlay(alignment: isLeading ? .trailing : .leading) {
                Image(systemName: isLeading ? "chevron.right" : "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 22, height: size.height)
                    .offset(x: isLeading ? -bleed : bleed)
            }
            .clipShape(shape)
            .frame(width: size.width + 2 * bleed, height: size.height + 2 * bleed)
            .accessibilityHidden(true)
    }
}
