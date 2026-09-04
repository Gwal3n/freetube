import SwiftUI

import Kingfisher

/// Crops one frame from YouTube's storyboard sprite sheet while the user previews a seek target.
@available(iOS 17.0, *)
struct StoryboardPreview: View {
    let tile: VideoStoryboard.Tile

    private let previewWidth: CGFloat = 116

    private var previewHeight: CGFloat {
        guard tile.width > 0 else { return 66 }
        return min(previewWidth * CGFloat(tile.height) / CGFloat(tile.width), 72)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            KFImage(tile.url)
                .resizable()
                .frame(
                    width: previewWidth * CGFloat(tile.columns),
                    height: previewHeight * CGFloat(tile.rows)
                )
                .offset(
                    x: -previewWidth * CGFloat(tile.column),
                    y: -previewHeight * CGFloat(tile.row)
                )
        }
        .frame(width: previewWidth, height: previewHeight, alignment: .topLeading)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.92), lineWidth: 1.5)
        }
        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }
}
