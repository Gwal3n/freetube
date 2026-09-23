import SwiftUI

import Kingfisher

/// Crops one frame from YouTube's storyboard sprite sheet while the user previews a seek target.
@available(iOS 17.0, *)
struct StoryboardPreview: View {
    let tile: VideoStoryboard.Tile
    let videoPresentationSize: CGSize

    private let maximumPreviewWidth: CGFloat = 116
    private let maximumPreviewHeight: CGFloat = 96

    private var previewSize: CGSize {
        let sourceAspect = tile.width > 0 && tile.height > 0
            ? CGFloat(tile.width) / CGFloat(tile.height)
            : 16 / 9
        let videoAspect = videoPresentationSize.width > 0 && videoPresentationSize.height > 0
            ? videoPresentationSize.width / videoPresentationSize.height
            : sourceAspect
        let aspect = max(0.2, min(videoAspect, 5))
        let width = min(maximumPreviewWidth, maximumPreviewHeight * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    var body: some View {
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
        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }
}
