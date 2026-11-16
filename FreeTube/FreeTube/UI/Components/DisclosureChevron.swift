import SwiftUI

/// The single glyph for content that expands in place: a trailing chevron that rotates from
/// right to down, matching native disclosure groups. Navigation and load-more actions use
/// their own glyphs.
struct DisclosureChevron: View {
    let isExpanded: Bool
    var font: Font = .footnote.weight(.semibold)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "chevron.right")
            .font(font)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(reduceMotion ? nil : InterfaceMotion.quick, value: isExpanded)
            .accessibilityHidden(true)
    }
}
