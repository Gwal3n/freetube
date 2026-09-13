import SwiftUI
import UIKit

/// Paints the current video's thumbnail into the player area for as long as AVPlayer has no frame
/// to show, then gets out of the way.
///
/// This is the perception half of the startup work. Resolution is down to ~0.4s on a warm cache but
/// AVPlayer still needs ~2s to reach `.readyToPlay`, and AVPlayer exposes no "first frame rendered"
/// signal we could paint against, so the wait can't be removed — only covered. NewPipe gets its
/// "instant" feel the same way: the thumbnail the user just tapped is already decoded in memory, so
/// showing it means the player area is never a black rectangle and never a spinner with a label.
///
/// Ordered *above* `PlayerSurface` in the ZStack on purpose — `AVPlayerViewController`'s view paints
/// its own opaque black background, so anything underneath it is invisible. `allowsHitTesting(false)`
/// keeps the system playback controls reachable through the artwork.
@available(iOS 17.0, *)
struct PlayerArtworkBackdrop: View {
    let artwork: UIImage?
    let state: PlayerStateManager.LoadState
    let forceVisible: Bool

    var body: some View {
        ZStack {
            Group {
                if coversPlayerSurface, let artwork {
                    artworkView(artwork)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: coversPlayerSurface)

            if forceVisible {
                Group {
                    if let artwork {
                        artworkView(artwork)
                    } else {
                        Color.black
                    }
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func artworkView(_ artwork: UIImage) -> some View {
        Image(uiImage: artwork)
            .resizable()
            // `.fill` rather than `.fit`: YouTube's `hqdefault` thumbnails are 4:3 with the frame
            // letterboxed inside them. Filling crops those baked-in bars from the player surface.
            .aspectRatio(contentMode: .fill)
            .clipped()
    }

    /// True while the player has nothing of its own to draw. `.failed` is included so the error
    /// message reads over the thumbnail instead of over black.
    private var coversPlayerSurface: Bool {
        switch state {
        case .resolving, .buffering, .downloading, .failed:
            return true
        case .idle, .readyToPlay:
            return false
        }
    }
}
