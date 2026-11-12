import SwiftUI

/// The same compact material badge for held speed and seek-preview feedback. The plain variant
/// drops the capsule for a less intrusive shadowed label.
@available(iOS 17.0, *)
struct PlayerGestureBadge: View {
    let text: String
    var isPlain = false

    var body: some View {
        let label = Text(verbatim: text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
        if isPlain {
            label
                .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
        } else {
            label
                .padding(.horizontal, 10)
                .frame(minWidth: 52, minHeight: 26)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
        }
    }
}
