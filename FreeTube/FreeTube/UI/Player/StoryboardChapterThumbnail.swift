import SwiftUI

import Kingfisher

/// Crops one storyboard frame for a chapter row when YouTube did not supply a chapter thumbnail.
@available(iOS 17.0, *)
struct StoryboardChapterThumbnail: View {
    let storyboard: VideoStoryboard
    let time: TimeInterval
    let duration: TimeInterval
    let size: CGSize

    var body: some View {
        Group {
            if let tile = storyboard.tile(
                at: time,
                duration: duration,
                maximumWidth: 160,
                maximumHeight: 90
            ) {
                let tileSize = CGSize(
                    width: size.width * CGFloat(tile.columns),
                    height: size.height * CGFloat(tile.rows)
                )
                ZStack(alignment: .topLeading) {
                    KFImage(tile.url)
                        .resizable()
                        .frame(width: tileSize.width, height: tileSize.height)
                        .offset(
                            x: -size.width * CGFloat(tile.column),
                            y: -size.height * CGFloat(tile.row)
                        )
                }
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
            } else {
                ZStack {
                    Color.primary.opacity(0.08)
                    Image(systemName: "play.rectangle")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
