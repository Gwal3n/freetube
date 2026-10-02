import SwiftUI
import Kingfisher

@available(iOS 17.0, *)
struct ChannelContextPreview: View {
    let channel: Channel
    @State private var metadata = ChannelPreviewMetadataStore.shared

    var body: some View {
        let details = metadata.enriched(channel)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                KFImage(details.thumbnailURL)
                    .thumbnail(size: CGSize(width: 64, height: 64)) { Circle().fill(MediaStyle.placeholderFill) }
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: details.name)
                        .font(.headline)
                        .lineLimit(2)
                    if let handle = details.handle, !handle.isEmpty {
                        Text(verbatim: handle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if details.subscriberCount != nil || details.videoCount != nil {
                HStack(spacing: 5) {
                    if let count = details.subscriberCount {
                        Text("\(count.formatted(.number.notation(.compactName))) subscribers")
                    }
                    if details.subscriberCount != nil && details.videoCount != nil {
                        Text(verbatim: "·")
                    }
                    if let count = details.videoCount {
                        Text("\(count.formatted()) videos")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            } else if metadata.isLoading(channel.id) {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Loading channel details")
            }

            if let description = details.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Text(verbatim: description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .task(id: channel.id) {
            await metadata.loadIfNeeded(for: channel)
        }
    }
}
