import SwiftUI

/// Full-width disclosure label with the same alignment and touch height across player sections.
struct PlayerSectionHeading: View {
    let title: String
    var detail: String? = nil
    let isExpanded: Bool
    var showsDisclosureIndicator = true

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .appFont(.headline, weight: .semibold)
                .lineLimit(1)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 8)
            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                    .contentShape(Circle())
            }
        }
        .frame(minHeight: 44)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}
