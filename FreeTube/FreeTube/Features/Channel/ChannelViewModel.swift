import Foundation
import Observation

@available(iOS 17.0, *)
@Observable
@MainActor
final class ChannelViewModel {
    /// Identifies which channel content destination a paginated request should target. Video sort
    /// state is tracked independently by `ChannelVideoSort` below.
    enum Tab: String, CaseIterable, Identifiable {
        case allVideos, shorts, directs, playlists
        var id: String { rawValue }
    }

    let channelID: String
    private(set) var details: ChannelDetails?
    private(set) var isLoading: Bool = false
    /// True while a per-tab continuation request is in flight. Used by the tab screen to avoid
    /// firing duplicate "load more" requests when the user is rapidly scrolling near the bottom.
    private(set) var isLoadingMore: [Tab: Bool] = [:]
    private(set) var videoTabs: [ChannelVideoSort: ChannelTab<Video>] = [:]
    private(set) var loadingVideoSorts: Set<ChannelVideoSort> = []
    private(set) var loadingMoreVideoSorts: Set<ChannelVideoSort> = []
    var errorState: ErrorState?

    private let service: any ChannelServicing
    private let localSubscriptions: LocalSubscriptionStore

    init(
        channelID: String,
        service: any ChannelServicing = ChannelService(),
        localSubscriptions: LocalSubscriptionStore = .shared
    ) {
        self.channelID = channelID
        self.service = service
        self.localSubscriptions = localSubscriptions
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedDetails = try await service.fetchChannel(id: channelID)
            details = loadedDetails
            videoTabs[.newest] = loadedDetails.videos
            if let channel = details?.channel, channel.isSubscribed {
                // An imported CSV has no artwork. Refresh its stored display metadata the first
                // time the user visits the channel, without changing subscription state.
                localSubscriptions.add(channel)
            }
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    /// Subscription is deliberately device-only. No YouTube account mutation is performed.
    func toggleSubscribe() async {
        guard let current = details else { return }
        let wasSubscribed = current.channel.isSubscribed
        if wasSubscribed {
            localSubscriptions.remove(channelID: current.channel.id)
        } else {
            localSubscriptions.add(current.channel)
        }
        // Optimistic flip — rebuild `details` without another channel request.
        let c = current.channel
        let updatedChannel = Channel(
            id: c.id,
            name: c.name,
            handle: c.handle,
            thumbnailURL: c.thumbnailURL,
            bannerURL: c.bannerURL,
            subscriberCount: c.subscriberCount,
            videoCount: c.videoCount,
            isSubscribed: !wasSubscribed,
            descriptionText: c.descriptionText
        )
        details = ChannelDetails(
            channel: updatedChannel,
            videos: current.videos,
            shorts: current.shorts,
            directs: current.directs,
            playlists: current.playlists
        )
    }

    /// True when YouTubeKit still has a continuation token for the underlying content tab.
    func canLoadMore(for tab: Tab) -> Bool {
        guard let details else { return false }
        if isLoadingMore[tab] == true { return false }
        switch tab {
        case .allVideos:
            return details.videos.continuationToken != nil
        case .shorts:
            return details.shorts.continuationToken != nil
        case .directs:
            return details.directs.continuationToken != nil
        case .playlists:
            return details.playlists.continuationToken != nil
        }
    }

    /// Appends the next page of items for the given tab onto `details`. SwiftUI views observing
    /// `details` re-render automatically because we replace the whole struct (and `@Observable`
    /// tracks the property).
    func loadMore(for tab: Tab) async {
        guard canLoadMore(for: tab), let current = details else { return }
        isLoadingMore[tab] = true
        defer { isLoadingMore[tab] = false }
        do {
            switch tab {
            case .allVideos:
                let next = try await service.fetchVideosNextPage(channelID: channelID)
                details = current.appendingVideos(next)
                videoTabs[.newest] = details?.videos
            case .shorts:
                let next = try await service.fetchShortsNextPage(channelID: channelID)
                details = current.appendingShorts(next)
            case .directs:
                let next = try await service.fetchDirectsNextPage(channelID: channelID)
                details = current.appendingDirects(next)
            case .playlists:
                let next = try await service.fetchPlaylistsNextPage(channelID: channelID)
                details = current.appendingPlaylists(next)
            }
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    func videos(for sort: ChannelVideoSort) -> [Video] {
        if let tab = videoTabs[sort] { return tab.items }
        return sort == .newest ? (details?.videos.items ?? []) : []
    }

    func hasLoadedVideos(for sort: ChannelVideoSort) -> Bool {
        sort == .newest ? details != nil : videoTabs[sort] != nil
    }

    func isLoadingVideos(for sort: ChannelVideoSort) -> Bool {
        loadingVideoSorts.contains(sort)
    }

    func loadVideos(sort: ChannelVideoSort) async {
        guard videoTabs[sort] == nil, !loadingVideoSorts.contains(sort) else { return }
        loadingVideoSorts.insert(sort)
        defer { loadingVideoSorts.remove(sort) }
        do {
            let remote = try await service.fetchVideos(channelID: channelID, sort: sort)
            if remote.items.isEmpty, !(details?.videos.items.isEmpty ?? true) {
                throw YouTubeServiceError.decoding(NSError(
                    domain: "ChannelViewModel",
                    code: -5,
                    userInfo: [NSLocalizedDescriptionKey: "YouTube returned an empty sorted Videos tab."]
                ))
            }
            videoTabs[sort] = remote
        } catch {
            // Preserve the old behavior as an explicit fallback: sort the already-loaded newest
            // page locally, but do not pretend it is a complete server-sorted result.
            videoTabs[sort] = ChannelTab(
                items: sort.localFallback(details?.videos.items ?? []),
                continuationToken: nil
            )
            errorState = ErrorState(from: error)
        }
    }

    func canLoadMoreVideos(sort: ChannelVideoSort) -> Bool {
        videoTabs[sort]?.continuationToken != nil && !loadingMoreVideoSorts.contains(sort)
    }

    func loadMoreVideos(sort: ChannelVideoSort) async {
        guard canLoadMoreVideos(sort: sort), let current = videoTabs[sort] else { return }
        loadingMoreVideoSorts.insert(sort)
        defer { loadingMoreVideoSorts.remove(sort) }
        do {
            let page: ChannelTab<Video>
            if sort == .newest {
                page = try await service.fetchVideosNextPage(channelID: channelID)
                details = details?.appendingVideos(page)
            } else {
                page = try await service.fetchVideosNextPage(channelID: channelID, sort: sort)
            }
            videoTabs[sort] = ChannelTab(
                items: current.items + page.items,
                continuationToken: page.continuationToken
            )
        } catch {
            errorState = ErrorState(from: error)
        }
    }
}

private extension ChannelDetails {
    func appendingVideos(_ page: ChannelTab<Video>) -> ChannelDetails {
        ChannelDetails(
            channel: channel,
            videos: ChannelTab(items: videos.items + page.items, continuationToken: page.continuationToken),
            shorts: shorts,
            directs: directs,
            playlists: playlists
        )
    }
    func appendingShorts(_ page: ChannelTab<Video>) -> ChannelDetails {
        ChannelDetails(
            channel: channel,
            videos: videos,
            shorts: ChannelTab(items: shorts.items + page.items, continuationToken: page.continuationToken),
            directs: directs,
            playlists: playlists
        )
    }
    func appendingDirects(_ page: ChannelTab<Video>) -> ChannelDetails {
        ChannelDetails(
            channel: channel,
            videos: videos,
            shorts: shorts,
            directs: ChannelTab(items: directs.items + page.items, continuationToken: page.continuationToken),
            playlists: playlists
        )
    }
    func appendingPlaylists(_ page: ChannelTab<Playlist>) -> ChannelDetails {
        ChannelDetails(
            channel: channel,
            videos: videos,
            shorts: shorts,
            directs: directs,
            playlists: ChannelTab(items: playlists.items + page.items, continuationToken: page.continuationToken)
        )
    }
}
