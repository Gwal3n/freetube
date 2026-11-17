import SwiftUI

/// Trailing chevron for content that expands in place. Collapsed points down; expanded points
/// up — the Music / Podcasts section pattern. Navigation and load-more actions use their own glyphs.
struct DisclosureChevron: View {
    let isExpanded: Bool
    var font: Font = .footnote.weight(.semibold)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "chevron.down")
            .font(font)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .animation(reduceMotion ? nil : InterfaceMotion.quick, value: isExpanded)
            .accessibilityHidden(true)
    }
}
