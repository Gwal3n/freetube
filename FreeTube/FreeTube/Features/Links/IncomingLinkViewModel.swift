import Foundation
import Observation

/// Resolves only the metadata needed after an external link is received. Playback starts from
/// a local seed before this model requests metadata, just like direct links in Search.
@available(iOS 17.0, *)
@Observable
@MainActor
final class IncomingLinkViewModel {
    var errorState: ErrorState?

    private let searchService: any SearchServicing
    private let videoService: any VideoServicing

    init(
        searchService: any SearchServicing = SearchService(),
        videoService: any VideoServicing = VideoService()
    ) {
        self.searchService = searchService
        self.videoService = videoService
    }

    func metadata(for videoID: String) async -> Video? {
        (try? await videoService.fetchInfo(id: videoID))?.video
    }

    /// A channel handle is not a browse ID. Search for an exact handle rather than pushing the
    /// handle into ChannelService's browse-ID endpoint or choosing an unrelated first result.
    func channelID(for handle: String) async -> String? {
        do {
            let results = try await searchService.search(query: handle)
            let wanted = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")).lowercased()
            return results.channels.first { channel in
                guard let candidate = channel.handle else { return false }
                return candidate.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                    .lowercased() == wanted
            }?.id
        } catch {
            return nil
        }
    }
}
