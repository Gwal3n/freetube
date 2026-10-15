import Foundation

/// Interleaves related uploads without turning the feed into an unrelated or random order.
/// Each loaded page is handled independently, so loading more cannot reshuffle earlier pages.
enum SubscriptionFeedOrdering {
    struct Configuration {
        let isEnabled: Bool
        let channelGap: Int
        let groupGap: Int
        let maximumDateShift: TimeInterval
        let groups: [SubscriptionGroup]
        let selectedGroupID: UUID?

        init(
            isEnabled: Bool = true,
            channelGap: Int = 2,
            groupGap: Int = 2,
            maximumDateShift: TimeInterval = 24 * 60 * 60,
            groups: [SubscriptionGroup] = [],
            selectedGroupID: UUID? = nil
        ) {
            self.isEnabled = isEnabled
            self.channelGap = channelGap
            self.groupGap = groupGap
            self.maximumDateShift = maximumDateShift
            self.groups = groups
            self.selectedGroupID = selectedGroupID
        }
    }

    static func diversified(
        _ snapshots: [SubscriptionFeedSnapshot],
        pageSize: Int,
        configuration: Configuration = Configuration()
    ) -> [SubscriptionFeedSnapshot] {
        guard configuration.isEnabled, snapshots.count > 1, pageSize > 0 else { return snapshots }
        var result = snapshots
        let channelGap = max(0, min(configuration.channelGap, 5))
        let groupGap = max(0, min(configuration.groupGap, 5))
        let maximumDateShift = max(0, configuration.maximumDateShift)
        let memberships = groupMemberships(configuration.groups, excluding: configuration.selectedGroupID)

        for pageStart in stride(from: 0, to: result.count, by: pageSize) {
            let pageEnd = min(pageStart + pageSize, result.count)
            guard pageEnd - pageStart > 1 else { continue }

            for index in (pageStart + 1)..<pageEnd {
                let history = result[max(pageStart, index - max(channelGap, groupGap))..<index]
                let currentScore = conflictScore(result[index], after: history,
                                                 channelGap: channelGap, groupGap: groupGap,
                                                 memberships: memberships)
                guard currentScore > 0 else { continue }
                var bestIndex = index
                var bestScore = currentScore
                // A bounded lookahead keeps the feed recognizably chronological even with many
                // uploads from one channel. Ties retain the original newest-first order.
                let searchEnd = min(pageEnd, index + 21)
                for candidateIndex in (index + 1)..<searchEnd {
                    let candidate = result[candidateIndex]
                    guard abs(result[index].sortDate.timeIntervalSince(candidate.sortDate)) <= maximumDateShift else {
                        continue
                    }
                    let score = conflictScore(candidate, after: history,
                                              channelGap: channelGap, groupGap: groupGap,
                                              memberships: memberships)
                    if score < bestScore {
                        bestIndex = candidateIndex
                        bestScore = score
                        if score == 0 { break }
                    }
                }
                if bestIndex != index {
                    let promoted = result.remove(at: bestIndex)
                    result.insert(promoted, at: index)
                }
            }
        }
        return result
    }

    private static func groupMemberships(
        _ groups: [SubscriptionGroup], excluding selectedGroupID: UUID?
    ) -> [String: Set<UUID>] {
        var memberships: [String: Set<UUID>] = [:]
        for group in groups where group.id != selectedGroupID {
            for channelID in group.channelIDs {
                memberships[channelID, default: []].insert(group.id)
            }
        }
        return memberships
    }

    private static func conflictScore(
        _ candidate: SubscriptionFeedSnapshot,
        after history: ArraySlice<SubscriptionFeedSnapshot>,
        channelGap: Int,
        groupGap: Int,
        memberships: [String: Set<UUID>]
    ) -> Int {
        let channelID = candidate.video.channelID
        let candidateGroups = memberships[channelID] ?? []
        var score = 0
        for (offset, previous) in history.reversed().enumerated() {
            let distance = offset + 1
            if distance <= channelGap, !channelID.isEmpty,
               channelID == previous.video.channelID {
                score += 100 * (channelGap - distance + 1)
            }
            if distance <= groupGap, !candidateGroups.isEmpty,
               !candidateGroups.isDisjoint(with: memberships[previous.video.channelID] ?? []) {
                score += 10 * (groupGap - distance + 1)
            }
        }
        return score
    }
}
