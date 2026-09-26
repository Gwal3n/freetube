import SwiftUI
import UIKit

@available(iOS 17.0, *)
struct ChannelContextMenuModifier: ViewModifier {
    let channel: Channel
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.openURL) private var openURL
    private let subscriptions = LocalSubscriptionStore.shared

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                MediaContextNavigation.open(.freetubeOpenChannel, id: channel.id, player: player)
            } label: { Label("Open channel", systemImage: "person.crop.circle") }
            if let url = channel.youtubeURL {
                ShareLink(item: url) { Label("Share channel", systemImage: "square.and.arrow.up") }
                Button { UIPasteboard.general.string = url.absoluteString } label: {
                    Label("Copy URL", systemImage: "link")
                }
                Button { openURL(url) } label: { Label("Open in browser", systemImage: "safari") }
            }
            Divider()
            Button {
                if subscriptions.contains(channel.id) {
                    subscriptions.remove(channelID: channel.id)
                } else {
                    subscriptions.add(channel)
                }
            } label: {
                Label(
                    subscriptions.contains(channel.id) ? "Unsubscribe" : "Subscribe",
                    systemImage: subscriptions.contains(channel.id) ? "person.badge.minus" : "person.badge.plus"
                )
            }
        } preview: {
            ChannelContextPreview(channel: channel)
        }
    }
}

extension View {
    @available(iOS 17.0, *)
    func channelContextMenu(channel: Channel) -> some View {
        modifier(ChannelContextMenuModifier(channel: channel))
    }
}
