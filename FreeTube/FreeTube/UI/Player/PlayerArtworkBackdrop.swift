import SwiftUI
import UIKit

/// Thumbnail cover while AVPlayer has no frame. Must sit above `PlayerSurface` and ignore hits.
@available(iOS 17.0, *)
struct PlayerArtworkBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let artwork: UIImage?
    let state: PlayerStateManager.LoadState
    let isAudioOnly: Bool

    var body: some View {
        Group {
            if coversPlayerSurface, let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    // Fill crops 4:3 YouTube hqdefault letterboxing out of the 16:9 surface.
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : InterfaceMotion.quick, value: coversPlayerSurface)
    }

    /// True while the player has nothing of its own to draw. `.failed` is included so the error
    /// message reads over the thumbnail instead of over black.
    private var coversPlayerSurface: Bool {
        switch state {
        case .resolving, .buffering, .downloading, .failed:
            return true
        case .readyToPlay:
            return isAudioOnly
        case .idle:
            return false
        }
    }
}
