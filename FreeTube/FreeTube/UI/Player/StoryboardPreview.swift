import SwiftUI

import Kingfisher

/// Crops one frame from YouTube's storyboard sprite sheet while the user previews a seek target.
@available(iOS 17.0, *)
struct StoryboardPreview: View {
    let tile: VideoStoryboard.Tile
    let time: TimeInterval

    private let previewWidth: CGFloat = 160

    private var previewHeight: CGFloat {
        guard tile.width > 0 else { return 90 }
        return min(previewWidth * CGFloat(tile.height) / CGFloat(tile.width), 100)
    }

    var body: some View {
        VStack(spacing: 4) {
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

            Text(verbatim: format(time))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(5)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }

    private func format(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
