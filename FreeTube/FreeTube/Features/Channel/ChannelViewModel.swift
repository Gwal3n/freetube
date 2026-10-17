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
    // The screen schedules its initial load on appearance. Reserve loading geometry from the
    // first frame, rather than briefly showing the idle/retry state before `.task` starts.
    private(set) var isLoading: Bool = true
    private(set) var isRefreshing = false
    private(set) var initialLoadFailed = false
    /// True while a per-tab continuation request is in flight. Used by the tab screen to avoid
    /// firing duplicate "load more" requests when the user is rapidly scrolling near the bottom.
    private(set) var isLoadingMore: [Tab: Bool] = [:]
    private(set) var videoTabs: [ChannelVideoSort: ChannelTab<Video>] = [:]
    private(set) var loadingVideoSorts: Set<ChannelVideoSort> = []
    private(set) var loadingMoreVideoSorts: Set<ChannelVideoSort> = []
    var errorState: ErrorState?

    private let service: any ChannelServicing
    private let localSubscriptions: LocalSubscriptionStore
    private let writer: PersistenceWriter
    @ObservationIgnored private var initialLoadTask: Task<Void, Never>?

    init(
        channelID: String,
        service: any ChannelServicing = ChannelService(),
        localSubscriptions: LocalSubscriptionStore = .shared,
        writer: PersistenceWriter = .shared
    ) {
        self.channelID = channelID
        self.service = service
        self.localSubscriptions = localSubscriptions
        self.writer = writer
    }

    func load() async {
        if let task = initialLoadTask {
            // Reopening joins the same request instead of exiting while the cancelled view's
            // task owns it. This task belongs to this channel model, not a view appearance.
            await task.value
            return
        }
        initialLoadFailed = false
        errorState = nil
        isLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performInitialLoad()
        }
        initialLoadTask = task
        await task.value
    }

    /// Pull-to-refresh keeps the current page visible until a complete replacement is ready.
    /// Only this channel is fetched; a subscribed channel also updates its local feed rows.
    func refresh(activeSort: ChannelVideoSort = .newest) async {
        guard details != nil else {
            await load()
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await load()
        guard errorState == nil, let refreshed = details else { return }
        let previousSort = activeSort == .newest ? nil : videoTabs[activeSort]
        videoTabs = [.newest: refreshed.videos]
        if let previousSort { videoTabs[activeSort] = previousSort }
        if activeSort != .newest {
            do {
                let remote = try await service.fetchVideos(channelID: channelID, sort: activeSort)
                if !remote.items.isEmpty { videoTabs[activeSort] = enrichingChannelMetadata(in: remote) }
            } catch {
                // The existing sorted page remains usable if this optional request fails.
                errorState = ErrorState(from: error)
            }
        }
        // An unexpectedly empty Videos tab can be a parser miss. Do not erase the cached feed
        // for that channel merely because this optional channel-page refresh returned no rows.
        if !refreshed.videos.items.isEmpty,
           localSubscriptions.subscriptions.contains(where: { $0.id == channelID }) {
            await writer.replaceSubscriptionFeedChannel(
                channelID: channelID, videos: refreshed.videos.items, refreshedAt: .now
            )
            NotificationCenter.default.post(name: .subscriptionFeedChannelDidRefresh, object: nil)
        }
    }

    private func performInitialLoad() async {
        defer {
            isLoading = false
            initialLoadTask = nil
        }
        do {
            var loadedDetails = try await service.fetchChannel(id: channelID)
            if loadedDetails.channel.thumbnailURL == nil,
               let savedAvatar = localSubscriptions.subscriptions.first(where: { $0.id == channelID })?.thumbnailURL {
                loadedDetails = loadedDetails.replacingChannel(
                    loadedDetails.channel.withThumbnailURL(savedAvatar)
                )
            }
            details = loadedDetails
            videoTabs[.newest] = loadedDetails.videos
            if let channel = details?.channel, channel.isSubscribed {
                // An imported CSV has no artwork. Refresh its stored display metadata the first
                // time the user visits the channel, without changing subscription state.
                localSubscriptions.add(channel)
            }
            if loadedDetails.channel.thumbnailURL == nil {
                Task { [weak self] in await self?.hydrateAvatarIfNeeded() }
            }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            initialLoadFailed = details == nil
            errorState = ErrorState(from: error)
        }
    }

    private func hydrateAvatarIfNeeded() async {
        guard details?.channel.thumbnailURL == nil,
              let avatar = await service.fetchChannelAvatar(id: channelID),
              let current = details,
              current.channel.thumbnailURL == nil else { return }
        let updatedChannel = current.channel.withThumbnailURL(avatar)
        details = current.replacingChannel(updatedChannel)
        if updatedChannel.isSubscribed { localSubscriptions.add(updatedChannel) }
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
        details = current.replacingChannel(updatedChannel)
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
            videoTabs[sort] = enrichingChannelMetadata(in: remote)
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
            let enrichedPage = enrichingChannelMetadata(in: page)
            videoTabs[sort] = ChannelTab(
                items: current.items + enrichedPage.items,
                continuationToken: enrichedPage.continuationToken
            )
        } catch {
            errorState = ErrorState(from: error)
        }
    }

    /// Sorted channel responses sometimes omit owner metadata because every row implicitly belongs
    /// to the channel being browsed. Reattach the already-loaded header identity at this boundary so
    /// all row consumers receive complete `Video` values, including continuation pages.
    private func enrichingChannelMetadata(in tab: ChannelTab<Video>) -> ChannelTab<Video> {
        guard let channel = details?.channel else { return tab }
        return ChannelTab(
            items: tab.items.map { video in
                Video(
                    id: video.id,
                    title: video.title,
                    channelID: video.channelID.isEmpty ? channel.id : video.channelID,
                    channelName: video.channelName.isEmpty ? channel.name : video.channelName,
                    channelThumbnailURL: video.channelThumbnailURL ?? channel.thumbnailURL,
                    thumbnailURL: video.thumbnailURL,
                    duration: video.duration,
                    viewCount: video.viewCount,
                    publishedAt: video.publishedAt,
                    publishedRelative: video.publishedRelative,
                    descriptionSnippet: video.descriptionSnippet,
                    isLive: video.isLive,
                    isShort: video.isShort
                )
            },
            continuationToken: tab.continuationToken
        )
    }
}

private extension ChannelDetails {
    func replacingChannel(_ updated: Channel) -> ChannelDetails {
        ChannelDetails(
            channel: updated,
            videos: videos,
            shorts: shorts,
            directs: directs,
            playlists: playlists
        )
    }

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
