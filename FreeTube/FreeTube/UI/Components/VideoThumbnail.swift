import SwiftUI
import Kingfisher

/// Stable artwork geometry shared by browsing cards and rows.
struct VideoThumbnail: View {
    let video: Video
    let size: CGSize
    var progress: Double? = nil
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        KFImage(video.thumbnailURL)
            .thumbnail(size: size, scale: displayScale, fadeDuration: reduceMotion ? 0 : 0.15) {
                Rectangle().fill(.quaternary)
            }
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if !video.durationString.isEmpty {
                    Text(verbatim: video.durationString)
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(video.isLive ? Color.red : Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                        .padding(5)
                }
            }
            .overlay(alignment: .bottom) {
                if let progress, progress.isFinite {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Color.black.opacity(0.32)
                            Color.red.frame(width: proxy.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
