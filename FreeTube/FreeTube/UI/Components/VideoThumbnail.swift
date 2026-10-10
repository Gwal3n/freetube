import SwiftUI
import Kingfisher

/// Stable artwork geometry shared by browsing cards and rows.
struct VideoThumbnail: View {
    let video: Video
    let size: CGSize
    var progress: Double? = nil
    var cornerRadius: CGFloat = MediaStyle.thumbnailRadius
    var replacementData: Data? = nil
    var replacementCacheKey: String? = nil
    var compactBadge = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var savedMomentStore = SavedMomentStore.shared

    var body: some View {
        KFImage(video.thumbnailURL)
            .thumbnail(size: size, scale: displayScale, fadeDuration: reduceMotion ? 0 : 0.15) {
                Rectangle().fill(MediaStyle.placeholderFill)
            }
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay {
                if let replacementData, let replacementCacheKey {
                    KFImage(source: .provider(RawImageDataProvider(data: replacementData, cacheKey: replacementCacheKey)))
                        .thumbnail(size: size, scale: displayScale, fadeDuration: reduceMotion ? 0 : 0.15) {
                            Color.clear
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topLeading) {
                if savedMomentStore.hasMoments(for: video.id) {
                    Circle()
                        .fill(.orange)
                        .frame(width: compactBadge ? 7 : 8, height: compactBadge ? 7 : 8)
                        .overlay(Circle().strokeBorder(.black.opacity(0.65), lineWidth: 1))
                        .padding(compactBadge ? 5 : 7)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !video.durationString.isEmpty {
                    Text(verbatim: video.durationString)
                        .font(compactBadge ? .system(size: 9, weight: .semibold) : .caption2.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, compactBadge ? 4 : 5)
                        .padding(.vertical, compactBadge ? 1 : 2)
                        .background(video.isLive ? Color.red : Color.black.opacity(compactBadge ? 0.78 : 0.75), in: RoundedRectangle(cornerRadius: compactBadge ? 3 : 4))
                        .padding(compactBadge ? 3 : 5)
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
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
