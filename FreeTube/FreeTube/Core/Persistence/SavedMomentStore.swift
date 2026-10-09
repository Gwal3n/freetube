import Foundation
import Observation

/// Small, explicitly saved timestamp collection. UserDefaults keeps it independent of watch
/// history retention; AppBackupService includes the records in full exports.
@available(iOS 17.0, *)
@Observable
@MainActor
final class SavedMomentStore {
    static let shared = SavedMomentStore()

    nonisolated private static let defaultsKey = "com.leshko.freetube.savedMoments.v1"
    private let defaults: UserDefaults
    private(set) var moments: [SavedMoment]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([SavedMoment].self, from: data) {
            moments = stored.sorted { $0.savedAt > $1.savedAt }
        } else {
            moments = []
        }
    }

    @discardableResult
    func add(video: Video, time: TimeInterval, label: String? = nil) -> SavedMoment? {
        guard !video.isLive,
              YouTubeVideoLink.videoID(from: video.id, allowBareID: true) != nil,
              time.isFinite, time >= 0 else { return nil }
        let boundedTime = video.duration.flatMap { duration in
            duration.isFinite && duration > 0 ? max(0, min(time, duration - 0.25)) : nil
        } ?? time
        let cleanLabel = Self.normalizedLabel(label)
        if let index = moments.firstIndex(where: {
            $0.video.id == video.id && abs($0.time - boundedTime) < 1
        }) {
            if let cleanLabel, moments[index].label != cleanLabel {
                moments[index].label = cleanLabel
                persist()
            }
            return moments[index]
        }
        let moment = SavedMoment(
            id: UUID(), video: video, time: boundedTime, label: cleanLabel, savedAt: .now
        )
        moments.insert(moment, at: 0)
        persist()
        return moment
    }

    func rename(id: UUID, label: String?) {
        guard let index = moments.firstIndex(where: { $0.id == id }) else { return }
        moments[index].label = Self.normalizedLabel(label)
        persist()
    }

    func remove(id: UUID) {
        moments.removeAll { $0.id == id }
        persist()
    }

    func replaceAll(with restored: [SavedMoment]) {
        var seen = Set<UUID>()
        moments = restored.filter {
            seen.insert($0.id).inserted && !$0.video.isLive
                && YouTubeVideoLink.videoID(from: $0.video.id, allowBareID: true) != nil
                && $0.time.isFinite && $0.time >= 0
        }.sorted { $0.savedAt > $1.savedAt }
        persist()
    }

    private static func normalizedLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(80))
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(moments) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
