import SwiftUI

/// The same compact material badge for held speed and seek-preview feedback.
@available(iOS 17.0, *)
struct PlayerGestureBadge: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(minWidth: 52, minHeight: 26)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
    }
}
