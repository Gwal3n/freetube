import Foundation
import Observation

/// Resolves legacy History rows on demand. History stores channel names, not IDs, so
/// showing the action must not trigger a network request for every visible row.
@available(iOS 17.0, *)
@Observable
@MainActor
final class LocalHistoryChannelNavigationModel {
    var errorState: ErrorState?
    private var channelIDs: [String: String] = [:]
    private var pendingVideoIDs: Set<String> = []
    private let videoService: any VideoServicing

    var isResolving: Bool { !pendingVideoIDs.isEmpty }

    init(videoService: any VideoServicing = VideoService()) {
        self.videoService = videoService
    }

    func channelID(for videoID: String) async -> String? {
        guard !pendingVideoIDs.contains(videoID) else { return nil }
        pendingVideoIDs.insert(videoID)
        defer { pendingVideoIDs.remove(videoID) }

        do {
            let channelID: String
            if let cached = channelIDs[videoID] {
                channelID = cached
            } else {
                channelID = try await videoService.fetchInfo(id: videoID).video.channelID
                guard !channelID.isEmpty else {
                    errorState = ErrorState(message: "This video's channel is unavailable.")
                    return nil
                }
                channelIDs[videoID] = channelID
            }
            return channelID
        } catch {
            errorState = ErrorState(from: error)
            return nil
        }
    }
}
