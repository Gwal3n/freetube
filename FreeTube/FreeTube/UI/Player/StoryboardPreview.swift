import SwiftUI

import Kingfisher

/// Crops one frame from YouTube's storyboard sprite sheet while the user previews a seek target.
@available(iOS 17.0, *)
struct StoryboardPreview: View {
    let tile: VideoStoryboard.Tile

    private let previewWidth: CGFloat = 132

    private var previewHeight: CGFloat {
        guard tile.width > 0 else { return 90 }
        return min(previewWidth * CGFloat(tile.height) / CGFloat(tile.width), 82)
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
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 0.75)
        }
        .padding(5)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }
}
