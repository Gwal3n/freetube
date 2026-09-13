import SwiftUI

/// Full-width disclosure label with the same alignment and touch height across player sections.
struct PlayerSectionHeading: View {
    let title: String
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(title).font(.headline)
            Spacer(minLength: 8)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}
