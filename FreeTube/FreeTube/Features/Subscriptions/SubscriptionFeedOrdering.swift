import Foundation

/// Softly interleaves channels when their cached upload times are effectively tied.
///
/// YouTube often provides relative dates rounded to a whole day, so a strict date sort can put
/// every upload from one channel in a run. A different channel may move ahead only when its next
/// upload is within six hours of the row it replaces. Each loaded page is handled independently:
/// appending another page never reorders videos the user has already scrolled past.
enum SubscriptionFeedOrdering {
    static func diversified(
        _ snapshots: [SubscriptionFeedSnapshot],
        pageSize: Int
    ) -> [SubscriptionFeedSnapshot] {
        guard snapshots.count > 1, pageSize > 0 else { return snapshots }
        var result = snapshots
        let nearTie: TimeInterval = 6 * 60 * 60

        for pageStart in stride(from: 0, to: result.count, by: pageSize) {
            let pageEnd = min(pageStart + pageSize, result.count)
            guard pageEnd - pageStart > 1 else { continue }

            for index in (pageStart + 1)..<pageEnd {
                let precedingChannel = result[index - 1].video.channelID
                guard result[index].video.channelID == precedingChannel,
                      index + 1 < pageEnd else { continue }
                let currentDate = result[index].sortDate
                guard let alternativeIndex = ((index + 1)..<pageEnd).first(where: { candidate in
                    result[candidate].video.channelID != precedingChannel
                        && currentDate.timeIntervalSince(result[candidate].sortDate) <= nearTie
                }) else { continue }

                let alternative = result.remove(at: alternativeIndex)
                result.insert(alternative, at: index)
            }
        }
        return result
    }
}
