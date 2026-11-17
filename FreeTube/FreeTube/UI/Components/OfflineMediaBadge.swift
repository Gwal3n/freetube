import SwiftUI

/// Marks on-device media: download-ready on thumbnails, or local-file playback in the player.
@available(iOS 17.0, *)
struct OfflineMediaBadge: View {
    enum Style {
        /// Icon-only corner mark for list/card artwork.
        case thumbnail(compact: Bool)
        /// Text label for the expanded player surface / metadata.
        case playerLabel
        /// Compact icon for the floating mini-player.
        case miniPlayer
    }

    let style: Style

    var body: some View {
        switch style {
        case .thumbnail(let compact):
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(compact ? 3 : 4)
                .background(Color.black.opacity(compact ? 0.78 : 0.75), in: Circle())
                .accessibilityLabel("Ready for offline playback")
        case .playerLabel:
            Label("Offline", systemImage: "arrow.down.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3))
                .accessibilityLabel("Playing offline")
        case .miniPlayer:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Color.black.opacity(0.6), in: Circle())
                .accessibilityLabel("Playing offline")
        }
    }
}
