import SwiftUI
import UIKit
import Kingfisher

@available(iOS 17.0, *)
struct PlaylistContextPreview: View {
    let playlist: Playlist
    var imageData: Data? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
                .scaledToFill()
                .frame(width: 320, height: 180)
                .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title).appFont(.headline, weight: .semibold).lineLimit(2)
                if let channel = playlist.channelName, !channel.isEmpty {
                    Text(channel).appFont(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let count = playlist.videoCount {
                    Text("\(count.formatted()) videos").appFont(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(width: 320)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var artwork: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image).resizable()
        } else {
            KFImage(playlist.thumbnailURL)
                .thumbnail(size: CGSize(width: 320, height: 180)) { MediaStyle.placeholderFill }
                .resizable()
        }
    }
}
