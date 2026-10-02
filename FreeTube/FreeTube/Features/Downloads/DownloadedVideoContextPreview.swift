import SwiftUI
import UIKit

/// Content for the system's lifted Haptic Touch preview of a locally downloaded file.
@available(iOS 17.0, *)
struct DownloadedVideoContextPreview: View {
    let item: SavedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let data = item.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    MediaStyle.placeholderFill
                        .overlay {
                            Image(systemName: "play.rectangle")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(width: 320, height: 180)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.channelName.isEmpty ? "Saved on this device" : item.channelName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(width: 320)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
