import SwiftUI

import Kingfisher

/// Crops one frame from YouTube's storyboard sprite sheet while the user previews a seek target.
@available(iOS 17.0, *)
struct StoryboardPreview: View {
    let tile: VideoStoryboard.Tile
    let videoPresentationSize: CGSize
    let previewTime: TimeInterval

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

            Text(verbatim: formattedPreviewTime)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.9), radius: 2, y: 1)
        }
        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
    }

    private var formattedPreviewTime: String {
        guard previewTime.isFinite, previewTime >= 0 else { return "0:00" }
        let total = Int(previewTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
