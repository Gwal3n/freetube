import Foundation

/// Fetches a bounded set of anonymous related videos for the local subscription feed.
/// Each source video costs one watch-page request; two requests run at a time.
@available(iOS 17.0, *)
@MainActor
final class FeedSuggestionService {
    private let videos: any VideoServicing

    init(videos: any VideoServicing = VideoService()) {
        self.videos = videos
    }

    func suggestions(for seeds: [Video]) async -> [Video] {
        var results: [Video] = []
        for start in stride(from: 0, to: seeds.count, by: 2) {
            guard !Task.isCancelled else { break }
            let batch = seeds[start..<min(start + 2, seeds.count)]
            let service = videos
            await withTaskGroup(of: [Video].self) { group in
                for seed in batch {
                    group.addTask {
                        guard !Task.isCancelled else { return [] }
                        let details = try? await service.fetchMoreInfo(id: seed.id)
                        return details?.recommended ?? []
                    }
                }
                for await videos in group { results.append(contentsOf: videos) }
            }
        }
        return results
    }
}
