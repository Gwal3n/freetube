import Foundation

/// Presentation-only filters for the video section of a submitted search. Search itself and
/// its continuation token remain untouched; missing metadata is excluded only when that filter
/// is active. Upload-age presets are approximate because YouTube returns relative text here.
struct SearchVideoFilters {
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
        case anytime, pastDay, pastWeek, pastMonth, pastYear, custom

        var id: String { rawValue }

        var title: String {
            switch self {
            case .anytime: "Any time"
            case .pastDay: "Past 24 hours"
            case .pastWeek: "Past week"
            case .pastMonth: "Past month"
            case .pastYear: "Past year"
            case .custom: "Custom date range…"
            }
        }

        var maximumAge: TimeInterval? {
            switch self {
            case .anytime: nil
            case .pastDay: 86_400
            case .pastWeek: 604_800
            case .pastMonth: 2_629_746
            case .pastYear: 31_556_952
            case .custom: nil
            }
        }

        func includes(_ video: Video, now: Date, customRange: DateRange?) -> Bool {
            if self == .custom {
                guard let customRange else { return false }
                let estimated = video.publishedAt
                    ?? Self.estimatedDate(from: video.publishedRelative, relativeTo: now)
                guard let estimated else { return false }
                return customRange.includes(estimated)
            }
            guard let maximumAge else { return true }
            let estimated = video.publishedAt
                ?? Self.estimatedDate(from: video.publishedRelative, relativeTo: now)
            guard let publishedAt = estimated else { return false }
            let age = now.timeIntervalSince(publishedAt)
            return age >= 0 && age <= maximumAge
        }

        private static func estimatedDate(from text: String?, relativeTo now: Date) -> Date? {
            guard let text = text?.lowercased(),
                  let numberRange = text.range(of: #"\d+"#, options: .regularExpression),
                  let count = Double(text[numberRange]) else { return nil }
            let seconds: TimeInterval
            if text.contains("second") { seconds = count }
            else if text.contains("minute") { seconds = count * 60 }
            else if text.contains("hour") { seconds = count * 3_600 }
            else if text.contains("day") { seconds = count * 86_400 }
            else if text.contains("week") { seconds = count * 604_800 }
            else if text.contains("month") { seconds = count * 2_629_746 }
            else if text.contains("year") { seconds = count * 31_556_952 }
            else { return nil }
            return now.addingTimeInterval(-seconds)
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

        func includes(_ duration: TimeInterval?, customRange: NumericRange?) -> Bool {
            guard self != .any else { return true }
            guard let duration, duration.isFinite, duration > 0 else { return false }
            return switch self {
            case .any: true
            case .underFourMinutes: duration < 240
            case .fourToTwentyMinutes: duration >= 240 && duration <= 1200
            case .overTwentyMinutes: duration > 1200
            case .custom: customRange.map {
                duration >= Double($0.minimum) * 60
                    && ($0.maximum.map { maximum in duration <= Double(maximum) * 60 } ?? true)
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

    var watch: Watch = .all
    var uploaded: Uploaded = .anytime
    var length: Length = .any
    var views: Views = .any
    var customUploadedRange: DateRange? = nil
    var customLengthRange: NumericRange? = nil
    var customViewsRange: NumericRange? = nil

    var isActive: Bool {
        watch != .all || uploaded != .anytime || length != .any || views != .any
    }

    func includes(_ video: Video, status: WatchHistoryStatus?, now: Date) -> Bool {
        watch.includes(status)
            && uploaded.includes(video, now: now, customRange: customUploadedRange)
            && length.includes(video.duration, customRange: customLengthRange)
            && views.includes(video.viewCount, customRange: customViewsRange)
    }
}
