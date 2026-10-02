import Foundation
import Observation

/// Serial playlist jobs above the existing single-video downloader. No stream extraction or
/// file writes are duplicated here: each item still goes through `DownloadManager`.
@available(iOS 17.0, *)
@Observable
@MainActor
final class PlaylistDownloadCoordinator {
    static let shared = PlaylistDownloadCoordinator()

    private(set) var manifests: [PlaylistDownloadManifest]
    private(set) var activePlaylistID: String?
    private(set) var currentVideoID: String?

    @ObservationIgnored private var workTask: Task<Void, Never>?
    @ObservationIgnored private var ownsCurrentTransfer = false
    @ObservationIgnored private let playlistService: any PlaylistServicing = PlaylistService()
    @ObservationIgnored private let manager = DownloadManager.shared
    @ObservationIgnored private let log = AppLog(subsystem: "com.leshko.freetube", category: "PlaylistDownloads")
    @ObservationIgnored private var saveTail: Task<Void, Never>?

    private static let archiveURL = AppDirectories.documents.deletingLastPathComponent()
        .appendingPathComponent("Library/Application Support/FreeTube/playlist-downloads.json")

    private init() {
        let stored = (try? Data(contentsOf: Self.archiveURL))
            .flatMap { try? JSONDecoder().decode([PlaylistDownloadManifest].self, from: $0) } ?? []
        // A process exit stops transfers. Never show a stale job as actively downloading.
        manifests = stored.map { item in
            var item = item
            if [.queued, .preparing, .downloading].contains(item.status) { item.status = .paused }
            return item
        }
    }

    /// The same remote playlist can be opened with or without YouTubeKit's browse prefix.
    static func canonicalID(_ id: String) -> String {
        id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    }

    func manifest(for playlistID: String) -> PlaylistDownloadManifest? {
        let id = Self.canonicalID(playlistID)
        return manifests.first { $0.id == id }
    }

    var protectedVideoIDs: Set<String> {
        Set(manifests.flatMap { $0.videos.map(\.id) })
    }

    /// Enqueues exactly one playlist job. Its initial page is already on screen; continuations
    /// are resolved by the worker before any video transfer begins.
    func start(_ details: PlaylistDetails, quality: VideoQuality) {
        let id = Self.canonicalID(details.playlist.id)
        guard !id.isEmpty, !details.videos.isEmpty || details.continuationToken != nil else { return }
        if let index = manifests.firstIndex(where: { $0.id == id }) {
            if activePlaylistID == id, manifests[index].status != .paused { return }
            manifests[index].status = .queued
            manifests[index].qualityRawValue = quality.rawValue
            manifests[index].lastError = nil
            manifests[index].updatedAt = .now
        } else {
            manifests.append(PlaylistDownloadManifest(
                id: id,
                title: details.playlist.title,
                thumbnailURL: details.playlist.thumbnailURL ?? details.videos.first?.thumbnailURL,
                videos: details.videos,
                continuationToken: details.continuationToken,
                qualityRawValue: quality.rawValue,
                failedVideoIDs: [],
                status: .queued,
                createdAt: .now,
                updatedAt: .now,
                lastError: nil
            ))
        }
        persist()
        pump()
    }

    func resume(_ playlistID: String) {
        let id = Self.canonicalID(playlistID)
        guard let index = manifests.firstIndex(where: { $0.id == id }) else { return }
        manifests[index].status = .queued
        manifests[index].lastError = nil
        manifests[index].updatedAt = .now
        persist()
        pump()
    }

    /// Cancellation keeps completed files and the playlist row for a later Resume.
    func cancel(_ playlistID: String) {
        let id = Self.canonicalID(playlistID)
        guard let index = manifests.firstIndex(where: { $0.id == id }) else { return }
        manifests[index].status = .paused
        manifests[index].updatedAt = .now
        persist()
        guard activePlaylistID == id else { return }
        workTask?.cancel()
        if ownsCurrentTransfer, let currentVideoID,
           let snapshot = manager.activeTasks.first(where: {
               $0.videoID == currentVideoID && Self.isRunning($0.state)
           }) {
            manager.cancel(taskID: snapshot.id)
        }
    }

    /// Removes grouping only; files shared with standalone downloads or other playlists stay.
    func remove(_ playlistID: String) {
        let id = Self.canonicalID(playlistID)
        cancel(id)
        manifests.removeAll { $0.id == id }
        persist()
    }

    private func pump() {
        guard workTask == nil,
              let next = manifests.first(where: { $0.status == .queued })?.id else { return }
        activePlaylistID = next
        workTask = Task { @MainActor in
            await process(next)
            activePlaylistID = nil
            currentVideoID = nil
            ownsCurrentTransfer = false
            workTask = nil
            pump()
        }
    }

    private func process(_ id: String) async {
        guard let index = manifests.firstIndex(where: { $0.id == id }),
              manifests[index].status == .queued,
              !Task.isCancelled else { return }
        manifests[index].status = .preparing
        persist()

        while let token = manifest(for: id)?.continuationToken {
            guard !Task.isCancelled, manifest(for: id)?.status != .paused else { return }
            do {
                let page = try await playlistService.fetchMore(continuation: token)
                guard !Task.isCancelled,
                      let position = manifests.firstIndex(where: { $0.id == id }),
                      manifests[position].status != .paused else { return }
                let known = Set(manifests[position].videos.map(\.id))
                manifests[position].videos.append(contentsOf: page.videos.filter { !known.contains($0.id) })
                manifests[position].continuationToken = page.continuationToken
                manifests[position].updatedAt = .now
                persist()
                if page.continuationToken == token {
                    update(id) { item in
                        item.status = .paused
                        item.lastError = "Playlist loading stalled. Tap Resume to try again."
                    }
                    return
                }
            } catch {
                guard !Task.isCancelled, manifest(for: id)?.status != .paused else { return }
                update(id) { item in
                    item.status = .paused
                    item.lastError = "Couldn’t load the rest of this playlist. Tap Resume to retry."
                }
                log.notice("Playlist continuation failed: \(String(describing: error), privacy: .public)")
                return
            }
        }

        guard let prepared = manifest(for: id), !Task.isCancelled,
              prepared.status != .paused else { return }
        update(id) { $0.status = .downloading }

        for video in prepared.videos {
            guard !Task.isCancelled, manifest(for: id)?.status != .paused else { return }
            if manager.localFile(for: video.id) != nil {
                update(id) { item in _ = item.failedVideoIDs.remove(video.id) }
                continue
            }
            currentVideoID = video.id
            ownsCurrentTransfer = !manager.activeTasks.contains {
                $0.videoID == video.id && Self.isRunning($0.state)
            }
            do {
                _ = try await manager.ensureDownloaded(video: video, quality: prepared.quality)
                guard !Task.isCancelled, manifest(for: id)?.status != .paused else { return }
                update(id) { item in _ = item.failedVideoIDs.remove(video.id) }
            } catch {
                guard !Task.isCancelled, manifest(for: id)?.status != .paused else { return }
                update(id) { item in _ = item.failedVideoIDs.insert(video.id) }
                log.notice("Playlist item failed \(video.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
            currentVideoID = nil
            ownsCurrentTransfer = false
        }

        guard !Task.isCancelled, manifest(for: id)?.status != .paused else { return }
        update(id) { item in
            item.status = .finished
            item.lastError = item.failedVideoIDs.isEmpty ? nil : "Some videos couldn’t be downloaded. Tap Retry to try again."
        }
    }

    private func update(_ id: String, _ change: (inout PlaylistDownloadManifest) -> Void) {
        guard let index = manifests.firstIndex(where: { $0.id == id }) else { return }
        change(&manifests[index])
        manifests[index].updatedAt = .now
        persist()
    }

    private static func isRunning(_ state: DownloadTaskSnapshot.State) -> Bool {
        switch state {
        case .queued, .downloading, .paused: return true
        case .completed, .failed: return false
        }
    }

    private func persist() {
        let snapshot = manifests
        let previous = saveTail
        let url = Self.archiveURL
        saveTail = Task.detached(priority: .utility) {
            await previous?.value
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                // The next mutation retries the archive. Transfers remain visible in memory.
            }
        }
    }
}
