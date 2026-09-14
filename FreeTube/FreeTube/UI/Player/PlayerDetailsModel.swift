import Foundation
import Observation

/// Owns the low-frequency metadata lifecycle for the expanded player.
///
/// Playback state remains in `PlayerStateManager`; this model only coordinates the cached details
/// request and derives strings consumed by `PlayerInformationPanel`. Keeping it separate prevents
/// metadata bookkeeping from accumulating in the player view itself.
@available(iOS 17.0, *)
@MainActor
@Observable
final class PlayerDetailsModel {
    private(set) var details: VideoInfo?
    private(set) var isLoading = false
    private(set) var loadFailed = false
    var isExpanded = false

    private var videoID: String?
    private var loadTask: Task<Void, Never>?
    private let store: VideoContentPrefetchStore

    init(store: VideoContentPrefetchStore = .shared) {
        self.store = store
    }

    deinit {
        loadTask?.cancel()
    }

    func reset(for videoID: String) {
        guard self.videoID != videoID else { return }
        loadTask?.cancel()
        loadTask = nil
        self.videoID = videoID
        details = nil
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
        isLoading = true
        loadFailed = false
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let info = try await store.fetchDetails(videoID: requestedVideoID)
                guard !Task.isCancelled,
                      videoID == requestedVideoID,
                      player.currentVideo?.id == requestedVideoID else { return }
                details = info
                player.installVideoDetails(info, for: requestedVideoID)
                let fetchedDescription = info.descriptionText?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                loadFailed = (fetchedDescription?.isEmpty ?? true)
                    && (descriptionSnippet?.isEmpty ?? true)
            } catch is CancellationError {
                // Changing videos cancels presentation work; the shared cache remains reusable.
            } catch {
                guard videoID == requestedVideoID,
                      player.currentVideo?.id == requestedVideoID else { return }
                loadFailed = true
            }

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
        if let viewsText = details?.viewCountText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !viewsText.isEmpty {
            parts.append(viewsText)
        } else if let views = video.viewCount, views > 0 {
            parts.append("\(Self.formatCount(views)) views")
        }
        if let uploadDate = details?.uploadDateText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !uploadDate.isEmpty {
            parts.append("Uploaded \(uploadDate)")
        } else if let published = video.publishedAt {
            parts.append("Uploaded \(published.formatted(date: .abbreviated, time: .omitted))")
        } else if let relative = video.publishedRelative, !relative.isEmpty {
            parts.append("Uploaded \(relative)")
        }
        return parts.joined(separator: " • ")
    }

    var likesText: String? {
        guard let count = details?.likeCount, count > 0 else { return nil }
        return Self.formatCount(count)
    }

    func commentsCountText(fallback: String?) -> String? {
        details?.commentsCountText ?? fallback
    }

    private static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.1fB", Double(count) / 1_000_000_000)
        }
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
