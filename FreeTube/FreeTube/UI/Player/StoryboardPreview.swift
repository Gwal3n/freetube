import SwiftUI
import UIKit

import Kingfisher

/// Crops one frame from YouTube's storyboard sprite sheet while the user previews a seek target.
@available(iOS 17.0, *)
struct StoryboardPreview: View {
    let tile: VideoStoryboard.Tile
    let videoPresentationSize: CGSize
    let style: SeekPreviewStyle

    private var previewSize: CGSize {
        let sourceAspect = tile.width > 0 && tile.height > 0
            ? CGFloat(tile.width) / CGFloat(tile.height)
            : 16 / 9
        let videoAspect = videoPresentationSize.width > 0 && videoPresentationSize.height > 0
            ? videoPresentationSize.width / videoPresentationSize.height
            : sourceAspect
        let aspect = max(0.2, min(videoAspect, 5))
        let width = min(style.maximumWidth, style.maximumHeight * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topLeading) {
                KFImage(tile.url)
                    .resizable()
                    .frame(
                        width: previewSize.width * CGFloat(tile.columns),
                        height: previewSize.height * CGFloat(tile.rows)
                    )
                    .offset(
                        x: -previewSize.width * CGFloat(tile.column),
                        y: -previewSize.height * CGFloat(tile.row)
                    )
            }
            .frame(width: previewSize.width, height: previewSize.height, alignment: .topLeading)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: 1.5)
            }
            // Keep the image's lower edge fixed across wide and tall videos so it always sits
            // just above the player's time labels.
            .frame(width: style.maximumWidth, height: style.maximumHeight, alignment: .bottom)

            timelineLabelClearance
        }
        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }
}

/// Audio-only seeks keep the same compact preview geometry, but never request moving storyboard
/// frames. The artwork is the static video thumbnail already used by the audio player surface.
@available(iOS 17.0, *)
struct AudioOnlySeekPreview: View {
    let artwork: UIImage?
    let thumbnailURL: URL?
    let style: SeekPreviewStyle

    var body: some View {
        VStack(spacing: 3) {
            Group {
                if let artwork {
                    Image(uiImage: artwork)
                        .resizable()
                } else if let thumbnailURL {
                    KFImage(thumbnailURL)
                        .resizable()
                } else {
                    Color.black
                }
            }
            .aspectRatio(contentMode: .fill)
            .frame(width: style.maximumWidth, height: style.maximumWidth * 9 / 16)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: 1.5)
            }
            .frame(width: style.maximumWidth, height: style.maximumHeight, alignment: .bottom)

            timelineLabelClearance
        }
        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }
}

/// Holds the tile above the timeline's time row, which shows the target time while scrubbing.
private var timelineLabelClearance: some View {
    Color.clear.frame(height: 26)
}
