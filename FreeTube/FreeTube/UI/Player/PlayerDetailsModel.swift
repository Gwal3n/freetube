import Foundation
import Observation

/// Owns the low-frequency metadata lifecycle for the expanded player.
/// Playback state remains in `PlayerStateManager`; this model only coordinates the cached details
/// request and derives strings consumed by `PlayerInformationPanel`. Keeping it separate prevents
/// metadata bookkeeping from accumulating in the player view itself.
@available(iOS 17.0, *)
@MainActor
@Observable
final class PlayerDetailsModel {
    private(set) var details: VideoInfo?
    private(set) var liveViewerCountText: String?
    private(set) var isLoading = false
    private(set) var loadFailed = false
    var isExpanded = false

    private var videoID: String?
    private var loadTask: Task<Void, Never>?
    private let store: VideoContentPrefetchStore

    init() {
        self.store = .shared
    }

    init(store: VideoContentPrefetchStore) {
        self.store = store
    }

    func reset(for videoID: String) {
        guard self.videoID != videoID else { return }
        loadTask?.cancel()
        loadTask = nil
        self.videoID = videoID
        details = nil
        liveViewerCountText = nil
        isLoading = false
        loadFailed = false
        isExpanded = false
    }

    func retry(for video: Video, player: PlayerStateManager) {
        details = nil
        loadFailed = false
        loadIfNeeded(for: video, player: player)
    }

    func loadIfNeeded(for video: Video, player: PlayerStateManager) {
        reset(for: video.id)
        guard details == nil, !isLoading else { return }

        let requestedVideoID = video.id
        let descriptionSnippet = video.descriptionSnippet?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let store = self.store
        isLoading = true
        loadFailed = false
        loadTask = Task { [weak self] in
            do {
                let info = try await store.fetchDetails(videoID: requestedVideoID)
                guard let self else { return }
                guard !Task.isCancelled,
                      videoID == requestedVideoID,
                      player.currentVideo?.id == requestedVideoID else { return }
                details = info
                liveViewerCountText = info.liveViewerCountText
                player.installVideoDetails(info, for: requestedVideoID)
                let fetchedDescription = info.descriptionText?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                loadFailed = (fetchedDescription?.isEmpty ?? true)
                    && (descriptionSnippet?.isEmpty ?? true)
            } catch is CancellationError {
                // Changing videos cancels presentation work; the shared cache remains reusable.
            } catch {
                guard let self else { return }
                guard videoID == requestedVideoID,
                      player.currentVideo?.id == requestedVideoID else { return }
                loadFailed = true
            }

            guard let self else { return }
            guard videoID == requestedVideoID else { return }
            isLoading = false
            loadTask = nil
        }
    }

    func description(for video: Video) -> String? {
        if let fetched = details?.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fetched.isEmpty {
            return fetched
        }
        if let snippet = video.descriptionSnippet?.trimmingCharacters(in: .whitespacesAndNewlines),
           !snippet.isEmpty {
            return snippet
        }
        return nil
    }

    func statsText(for video: Video) -> String {
        var parts: [String] = []
        if video.isLive {
            if let liveViewerCountText, !liveViewerCountText.isEmpty {
                parts.append(liveViewerCountText)
            }
        } else if let viewsText = details?.viewCountText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !viewsText.isEmpty {
            parts.append(Self.exactViewCount(in: viewsText).map(Video.viewCountLabel) ?? viewsText)
        } else if !video.viewCountString.isEmpty {
            parts.append(video.viewCountString)
        }
        if let count = details?.likeCount, count > 0 {
            parts.append(Video.likeCountLabel(count))
        }
        if let uploadDate = details?.uploadDateText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !uploadDate.isEmpty {
            parts.append(uploadDate)
        } else if let published = video.publishedAt {
            parts.append(published.formatted(date: .abbreviated, time: .omitted))
        } else if let relative = video.publishedRelative, !relative.isEmpty {
            parts.append(relative)
        }
        return parts.joined(separator: " • ")
    }

    /// Reads the number from the watch page's exact "5,364,808 views" text so the row can use the
    /// same compact style as likes. Anything else (labels, other wording) is shown unchanged.
    static func exactViewCount(in text: String) -> Int? {
        let lowered = text.lowercased()
        let suffixes = [" views", " view"]
        guard let suffix = suffixes.first(where: lowered.hasSuffix) else { return nil }
        let number = lowered.dropLast(suffix.count).filter { $0 != "," }
        guard !number.isEmpty, number.allSatisfy(\.isASCII), let count = Int(number), count > 0 else { return nil }
        return count
    }

    /// The shared details cache is useful for ordinary videos, but live viewership goes stale.
    /// Refresh only while the expanded live player is visible; its SwiftUI task owns cancellation.
    func refreshLiveViewerCount(for videoID: String, player: PlayerStateManager) async {
        guard !Task.isCancelled, player.currentVideo?.id == videoID else { return }
        reset(for: videoID)
        while !Task.isCancelled {
            do {
                let fresh = try await store.fetchDetails(videoID: videoID, maxAge: 60)
                guard !Task.isCancelled, self.videoID == videoID,
                      player.currentVideo?.id == videoID else { return }
                liveViewerCountText = fresh.liveViewerCountText
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, self.videoID == videoID else { return }
                liveViewerCountText = nil
            }
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
        }
    }

    func commentsCountText(fallback: String?) -> String? {
        details?.commentsCountText ?? fallback
    }
}
