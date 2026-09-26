import SwiftUI
import Kingfisher

@available(iOS 17.0, *)
struct ChannelContextPreview: View {
    let channel: Channel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            KFImage(channel.thumbnailURL)
                .thumbnail(size: CGSize(width: 64, height: 64)) { Circle().fill(MediaStyle.placeholderFill) }
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(channel.name).font(.headline).lineLimit(2)
                if let handle = channel.handle, !handle.isEmpty {
                    Text(handle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if let count = channel.subscriberCount {
                    Text("\(count.formatted(.number.notation(.compactName))) subscribers")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let count = channel.videoCount {
                    Text("\(count.formatted()) videos").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
