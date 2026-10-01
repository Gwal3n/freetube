import SwiftUI

/// Matching action chrome across public and on-device playlist headers.
@available(iOS 17.0, *)
struct PlaylistHeaderActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
            .frame(minHeight: MediaStyle.actionSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(ResponsiveButtonStyle())
    }
}
