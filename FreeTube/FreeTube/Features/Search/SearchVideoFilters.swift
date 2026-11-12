import Foundation

/// Hybrid search filters: YouTube-native constraints travel as InnerTube `params`, while
/// watch-history / view-count / custom ranges stay local. When the server path falls back to a
/// plain query, the mirrored upload/length presets are applied locally instead.
struct SearchVideoFilters: Equatable {
    struct NumericRange: Equatable {
        let minimum: Int
        /// Nil means no upper limit.
        let maximum: Int?

        func includes(_ value: Int) -> Bool {
            value >= minimum && (maximum.map { value <= $0 } ?? true)
        }
    }

    struct DateRange: Equatable {
        let firstDay: Date
        let lastDay: Date

        func includes(_ date: Date) -> Bool {
            let calendar = Calendar.autoupdatingCurrent
            let start = calendar.startOfDay(for: firstDay)
            guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay)) else {
                return false
            }
            return date >= start && date < end
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case relevance, uploadDate, viewCount, rating

        var id: String { rawValue }

        var title: String {
            switch self {
            case .relevance: "Relevance"
            case .uploadDate: "Upload date"
            case .viewCount: "View count"
            case .rating: "Rating"
            }
        }

        /// Protobuf field-1 value. Relevance is the default and may be omitted when alone.
        var serverValue: Int? {
            switch self {
            case .relevance: nil
            case .rating: 1
            case .uploadDate: 2
            case .viewCount: 3
            }
        }
    }

    enum ResultType: String, CaseIterable, Identifiable {
        case any, video, channel, playlist

        var id: String { rawValue }

        var title: String {
            switch self {
            case .any: "All results"
            case .video: "Videos"
            case .channel: "Channels"
            case .playlist: "Playlists"
            }
        }

        var serverValue: Int? {
            switch self {
            case .any: nil
            case .video: 1
            case .channel: 2
            case .playlist: 3
            }
        }

        /// Duration and upload-date filters only apply to video (and movie) results on YouTube.
        var supportsVideoConstraints: Bool {
            self == .any || self == .video
        }
    }

    enum Watch: String, CaseIterable, Identifiable {
        case all, hideWatched, hideUnwatched, onlyPartial, onlyFinished

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "Any watch status"
            case .hideWatched: "Hide watched"
            case .hideUnwatched: "Hide unwatched"
            case .onlyPartial: "Only partially watched"
            case .onlyFinished: "Only finished"
            }
        }

        func includes(_ status: WatchHistoryStatus?) -> Bool {
            return switch self {
            case .all: true
            case .hideWatched: status == nil
            case .hideUnwatched: status != nil
            case .onlyPartial: status == .partial
            case .onlyFinished: status == .finished
            }
        }
    }

    enum Uploaded: String, CaseIterable, Identifiable {
        case anytime, pastHour, pastDay, pastWeek, pastMonth, pastYear, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .anytime: "Any time"
            case .pastHour: "Last hour"
            case .pastDay: "Today"
            case .pastWeek: "This week"
            case .pastMonth: "This month"
            case .pastYear: "This year"
            case .custom: "Custom date range…"
            }
        }

        var serverValue: Int? {
            switch self {
            case .anytime, .custom: nil
            case .pastHour: 1
            case .pastDay: 2
            case .pastWeek: 3
            case .pastMonth: 4
            case .pastYear: 5
            }
        }

        var maximumAge: TimeInterval? {
            switch self {
            case .anytime, .custom: nil
            case .pastHour: 3_600
            case .pastDay: 86_400
            case .pastWeek: 604_800
            case .pastMonth: 2_629_746
            case .pastYear: 31_556_952
            }
        }

        func includes(_ video: Video, now: Date, customRange: DateRange?) -> Bool {
            if self == .custom {
                guard let customRange else { return false }
                let estimated = video.estimatedPublishedAt(relativeTo: now)
                guard let estimated else { return false }
                return customRange.includes(estimated)
            }
            guard let maximumAge else { return true }
            let estimated = video.estimatedPublishedAt(relativeTo: now)
            guard let publishedAt = estimated else { return false }
            let age = now.timeIntervalSince(publishedAt)
            return age >= 0 && age <= maximumAge
        }
    }

    enum Length: String, CaseIterable, Identifiable {
        case any, underFourMinutes, fourToTwentyMinutes, overTwentyMinutes, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .any: "Any length"
            case .underFourMinutes: "Under 4 minutes"
            case .fourToTwentyMinutes: "4–20 minutes"
            case .overTwentyMinutes: "Over 20 minutes"
            case .custom: "Custom duration…"
            }
        }

        var serverValue: Int? {
            switch self {
            case .any, .custom: nil
            case .underFourMinutes: 1
            case .overTwentyMinutes: 2
            case .fourToTwentyMinutes: 3
            }
        }

        func includes(_ duration: TimeInterval?, customRange: NumericRange?) -> Bool {
            guard self != .any else { return true }
            guard let duration, duration.isFinite, duration > 0 else { return false }
            return switch self {
            case .any: true
            case .underFourMinutes: duration < 240
            case .fourToTwentyMinutes: duration >= 240 && duration <= 1200
            case .overTwentyMinutes: duration > 1200
            case .custom: customRange.map {
                // Custom length ranges are stored in seconds.
                duration >= Double($0.minimum)
                    && ($0.maximum.map { maximum in duration <= Double(maximum) } ?? true)
            } ?? false
            }
        }
    }

    enum Views: String, CaseIterable, Identifiable {
        case any, underTenThousand, tenToHundredThousand, hundredThousandToMillion, overMillion, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .any: "Any view count"
            case .underTenThousand: "Under 10K views"
            case .tenToHundredThousand: "10K–100K views"
            case .hundredThousandToMillion: "100K–1M views"
            case .overMillion: "1M+ views"
            case .custom: "Custom view range…"
            }
        }

        func includes(_ count: Int?, customRange: NumericRange?) -> Bool {
            guard self != .any else { return true }
            guard let count, count >= 0 else { return false }
            return switch self {
            case .any: true
            case .underTenThousand: count < 10_000
            case .tenToHundredThousand: count >= 10_000 && count < 100_000
            case .hundredThousandToMillion: count >= 100_000 && count < 1_000_000
            case .overMillion: count >= 1_000_000
            case .custom: customRange?.includes(count) ?? false
            }
        }
    }

    /// Which catalog to search. Music results carry no upload dates and usually no durations,
    /// and the Music endpoint takes no sort/filter params, so those categories are disabled.
    enum Source: String, CaseIterable, Identifiable {
        case youtube, music

        var id: String { rawValue }

        var title: String {
            switch self {
            case .youtube: "YouTube"
            case .music: "YouTube Music"
            }
        }
    }

    var source: Source = .youtube
    var sort: Sort = .relevance
    var resultType: ResultType = .any
    var watch: Watch = .all
    var uploaded: Uploaded = .anytime
    var length: Length = .any
    var views: Views = .any
    var customUploadedRange: DateRange? = nil
    var customLengthRange: NumericRange? = nil
    var customViewsRange: NumericRange? = nil

    /// Default filters for the same source. The source is a search mode, not a narrowing filter,
    /// so it is excluded from `isActive` and survives resets and new queries.
    func resettingFilters() -> SearchVideoFilters {
        var filters = SearchVideoFilters()
        filters.source = source
        return filters
    }

    /// Music results have no upload dates or sort params and mostly lack durations, so those
    /// constraints are cleared rather than silently hiding every Music result.
    mutating func selectSource(_ newSource: Source) {
        source = newSource
        guard newSource == .music else { return }
        sort = .relevance
        uploaded = .anytime
        length = .any
    }

    var supportsServerConstraints: Bool {
        source == .youtube
    }

    /// Whether anything other than the result type narrows results. The type has its own picker
    /// beneath the Search title, so the filter menu's indicator and reset ignore it.
    var isNarrowedBeyondType: Bool {
        var withoutType = self
        withoutType.resultType = .any
        return withoutType.isActive
    }

    var isActive: Bool {
        sort != .relevance
            || resultType != .any
            || watch != .all
            || uploaded != .anytime
            || length != .any
            || views != .any
    }

    /// True when changing this filter requires a new YouTube search rather than local trimming.
    var affectsServerQuery: Bool {
        serverParams != nil
    }

    /// Everything that selects the remote request: catalog plus InnerTube `params`.
    var serverRequestKey: String {
        "\(source.rawValue)|\(serverParams ?? "")"
    }

    /// InnerTube `params` blob, or `nil` when the request should stay an unfiltered query.
    var serverParams: String? {
        guard source == .youtube else { return nil }
        let uploadedForServer = resultType.supportsVideoConstraints ? uploaded : .anytime
        let lengthForServer = resultType.supportsVideoConstraints ? length : .any
        return SearchParamsEncoder.encode(
            sort: sort,
            resultType: resultType,
            uploaded: uploadedForServer,
            length: lengthForServer
        )
    }

    /// - Parameter applyServerMirroredLocally: When `false`, upload/length presets that were already
    ///   sent to YouTube are not re-applied on the client (missing metadata would over-filter).
    ///   Set `true` after a plain-query fallback so those presets still take effect locally.
    ///   Defaults to `true` for local-only callers such as playlist filtering.
    func includes(
        _ video: Video,
        status: WatchHistoryStatus?,
        now: Date,
        applyServerMirroredLocally: Bool = true
    ) -> Bool {
        let applyUploadedLocally = applyServerMirroredLocally
            || uploaded == .custom
            || uploaded.serverValue == nil
        let applyLengthLocally = applyServerMirroredLocally
            || length == .custom
            || length.serverValue == nil
        return watch.includes(status)
            && (!applyUploadedLocally || uploaded.includes(video, now: now, customRange: customUploadedRange))
            && (!applyLengthLocally || length.includes(video.duration, customRange: customLengthRange))
            && views.includes(video.viewCount, customRange: customViewsRange)
    }
}
