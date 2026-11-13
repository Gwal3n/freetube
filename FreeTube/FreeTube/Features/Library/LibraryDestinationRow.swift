import SwiftUI

@available(iOS 17.0, *)
struct LibraryDestinationRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 28, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .appFont(.body)
                Text(subtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : InterfaceMotion.content, value: subtitle)
            }
            Spacer(minLength: 8)
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
