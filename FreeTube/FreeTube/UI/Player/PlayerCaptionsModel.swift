import Foundation
import Observation

/// Caption selection is local to the current video. Fetching tracks and cues never participates
/// in playback resolution, and changing videos cancels an in-flight cue request.
@available(iOS 17.0, *)
@Observable
@MainActor
final class PlayerCaptionsModel {
    @ObservationIgnored private let videoService: any VideoServicing
    @ObservationIgnored private var cueTask: Task<Void, Never>?

    private(set) var videoID: String?
    private(set) var tracks: [VideoCaptionTrack] = []
    private(set) var cues: [VideoCaptionCue] = []
    private(set) var selectedTrackID: String?
    private(set) var isLoadingTracks = false
    private(set) var isLoadingCues = false
    private(set) var hasTrackError = false
    private(set) var hasCueError = false
    private(set) var hasLoadedTracks = false

    init(videoService: any VideoServicing = VideoService()) {
        self.videoService = videoService
    }

    func reset(for videoID: String?) {
        guard self.videoID != videoID else { return }
        cueTask?.cancel()
        cueTask = nil
        self.videoID = videoID
        tracks = []
        cues = []
        selectedTrackID = nil
        isLoadingTracks = false
        isLoadingCues = false
        hasTrackError = false
        hasCueError = false
        hasLoadedTracks = false
    }

    func loadTracks(for videoID: String) async {
        guard self.videoID == videoID, !hasLoadedTracks, !isLoadingTracks else { return }
        isLoadingTracks = true
        hasTrackError = false
        defer {
            if self.videoID == videoID { isLoadingTracks = false }
        }
        do {
            let info = try await videoService.fetchInfo(id: videoID)
            guard !Task.isCancelled, self.videoID == videoID else { return }
            tracks = info.captionTracks
            hasLoadedTracks = true
        } catch {
            guard !Task.isCancelled, self.videoID == videoID else { return }
            hasTrackError = true
        }
    }

    func retryTracks() {
        guard let videoID else { return }
        Task { await loadTracks(for: videoID) }
    }

    func select(_ track: VideoCaptionTrack?) {
        cueTask?.cancel()
        cueTask = nil
        selectedTrackID = track?.id
        cues = []
        hasCueError = false
        isLoadingCues = false
        guard let track, let videoID else { return }

        isLoadingCues = true
        cueTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await videoService.fetchCaptionCues(videoID: videoID, track: track)
                guard !Task.isCancelled, selectedTrackID == track.id else { return }
                cues = loaded
            } catch {
                guard !Task.isCancelled, selectedTrackID == track.id else { return }
                hasCueError = true
            }
            if selectedTrackID == track.id { isLoadingCues = false }
        }
    }

    func retrySelectedTrack() {
        guard let track = tracks.first(where: { $0.id == selectedTrackID }) else { return }
        select(track)
    }
}
