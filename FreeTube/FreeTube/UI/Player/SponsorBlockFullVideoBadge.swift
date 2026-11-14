import SwiftUI

/// Corner icon on the player surface when the whole video carries a SponsorBlock full-video label.
@available(iOS 17.0, *)
struct SponsorBlockFullVideoBadge: View {
    let category: SponsorBlockCategory?
    @AppStorage("sponsorBlockShowFullVideoThumbnailBadge") private var showBadge = true
    @AppStorage("sponsorBlockColorOverridesJSON") private var overridesJSON = "{}"

    var body: some View {
        if showBadge,
           let category,
           let systemImage = category.fullVideoThumbnailSystemImage {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(6)
                .background(
                    SponsorBlockColorPalette(json: overridesJSON).color(for: category).opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .accessibilityLabel(category.fullVideoLabelName ?? category.displayName)
                .allowsHitTesting(false)
        }
    }
}
