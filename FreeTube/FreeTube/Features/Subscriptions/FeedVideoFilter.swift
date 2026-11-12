import Foundation

/// Feed's local filters. Watch status keeps Feed's own choices; length, upload date, and views
/// reuse Search's presets and matching so both filter menus offer the same options.
@available(iOS 17.0, *)
struct FeedVideoFilter: Equatable, Codable {
    var watch: FeedWatchFilter = .all
    var uploaded: SearchVideoFilters.Uploaded = .anytime
    var length: SearchVideoFilters.Length = .any
    var views: SearchVideoFilters.Views = .any
    var customUploadedRange: SearchVideoFilters.DateRange?
    /// Seconds, matching Search's custom duration ranges.
    var customLengthRange: SearchVideoFilters.NumericRange?
    var customViewsRange: SearchVideoFilters.NumericRange?

    var isActive: Bool {
        watch != .all || uploaded != .anytime || length != .any || views != .any
    }

    /// Everything except watch status, which needs a history lookup.
    func includesMetadata(_ video: Video, now: Date) -> Bool {
        uploaded.includes(video, now: now, customRange: customUploadedRange)
            && length.includes(video.duration, customRange: customLengthRange)
            && views.includes(video.viewCount, customRange: customViewsRange)
    }

    func includes(_ video: Video, status: WatchHistoryStatus?, now: Date) -> Bool {
        watch.includes(status) && includesMetadata(video, now: now)
    }

    // MARK: - Persistence

    private static let storageKey = "feedVideoFilter"

    /// Reads the saved filter, migrating the earlier separate watch/duration preferences once.
    static func load(_ defaults: UserDefaults = .standard) -> FeedVideoFilter {
        if let data = defaults.data(forKey: storageKey),
           let filter = try? JSONDecoder().decode(FeedVideoFilter.self, from: data) {
            return filter
        }
        var filter = FeedVideoFilter()
        if let raw = defaults.string(forKey: "feedWatchFilter"),
           let watch = FeedWatchFilter(rawValue: raw) {
            filter.watch = watch
        }
        // Preset raw values are shared with Search; the old "all" maps to the `.any` default.
        if let raw = defaults.string(forKey: "feedDurationFilter"),
           let length = SearchVideoFilters.Length(rawValue: raw) {
            filter.length = length
        }
        if filter.length == .custom {
            let minimumMinutes = max(0, defaults.integer(forKey: "feedCustomDurationMinimumMinutes"))
            let maximumMinutes = defaults.integer(forKey: "feedCustomDurationMaximumMinutes")
            filter.customLengthRange = .init(
                minimum: minimumMinutes * 60,
                maximum: maximumMinutes > 0 ? maximumMinutes * 60 : nil
            )
        }
        return filter
    }

    func save(_ defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

extension SearchVideoFilters.Uploaded: Codable {}
extension SearchVideoFilters.Length: Codable {}
extension SearchVideoFilters.Views: Codable {}
