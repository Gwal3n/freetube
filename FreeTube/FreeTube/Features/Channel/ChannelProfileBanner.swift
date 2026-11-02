import SwiftUI

import Kingfisher

/// Full-width artwork whose extra pixels extend behind the navigation and status areas.
/// The clear frame owns layout width; the scaled image lives in an overlay so wide banners cannot
/// expand the header beyond the screen.
@available(iOS 17.0, *)
struct ChannelProfileBanner: View {
    let channel: Channel?
    let headerOffset: CGFloat
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            // Counter the header's upward translation so the extended artwork stays steady.
            let topExtension = max(0, geometry.frame(in: .global).minY + headerOffset)
            let artworkHeight = height + topExtension

            Color.clear
                .frame(width: geometry.size.width, height: artworkHeight)
                .overlay {
                    if let bannerURL = channel?.bannerURL {
                        KFImage(bannerURL)
                            .thumbnail(size: CGSize(width: 900, height: 300)) {
                                bannerPlaceholder
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, height: artworkHeight)
                    } else {
                        bannerPlaceholder
                    }
                }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.55), location: 0),
                            .init(color: .clear, location: 0.35),
                            .init(color: .clear, location: 0.55),
                            .init(color: MediaStyle.pageBackground.opacity(0.95), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipped()
                .offset(y: -topExtension)
        }
        .frame(height: height)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var bannerPlaceholder: some View {
        LinearGradient(
            colors: [Color(white: 0.22), Color(white: 0.10)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
