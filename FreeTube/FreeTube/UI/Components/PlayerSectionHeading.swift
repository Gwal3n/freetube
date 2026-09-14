import SwiftUI

/// Full-width disclosure label with the same alignment and touch height across player sections.
struct PlayerSectionHeading: View {
    let title: String
    var detail: String? = nil
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.headline)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}
