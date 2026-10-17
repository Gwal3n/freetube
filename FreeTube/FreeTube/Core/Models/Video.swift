import Foundation

/// Domain model for a YouTube video. Service layer maps YouTubeKit response types into this.
struct Video: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let title: String
    let channelID: String
    let channelName: String
    let channelThumbnailURL: URL?
    let thumbnailURL: URL?
    let duration: TimeInterval?
    let viewCount: Int?
    let publishedAt: Date?
    /// Human-readable "N days ago" string from YouTube's `timePosted` field. We keep this as a
    /// separate display-ready string because YouTube only returns relative phrasing here
    /// ("3 days ago" / "2 months ago" / "1 year ago"). The subscription feed additionally
    /// derives an approximate date at refresh time so cached ages can advance on screen.
    let publishedRelative: String?
    let descriptionSnippet: String?
    let isLive: Bool
    let isShort: Bool
}

extension Video {
    /// Forwarding initializer that defaults `publishedRelative` to nil. Keeps the dozen
    /// existing call sites that construct `Video` literally (in VideoService, PlaybackResolver,
    /// LibraryScreen, DownloadsScreen, etc.) compiling without each one being touched — only
    /// places that have a real value (Mappers, channel/playlist backfill) need to pass it.
    init(
        id: String,
        title: String,
        channelID: String,
        channelName: String,
        channelThumbnailURL: URL?,
        thumbnailURL: URL?,
        duration: TimeInterval?,
        viewCount: Int?,
        publishedAt: Date?,
        descriptionSnippet: String?,
        isLive: Bool,
        isShort: Bool
    ) {
        self.init(
            id: id,
            title: title,
            channelID: channelID,
            channelName: channelName,
            channelThumbnailURL: channelThumbnailURL,
            thumbnailURL: thumbnailURL,
            duration: duration,
            viewCount: viewCount,
            publishedAt: publishedAt,
            publishedRelative: nil,
            descriptionSnippet: descriptionSnippet,
            isLive: isLive,
            isShort: isShort
        )
    }
}

extension Video {
    /// Public timestamp link only. Never share or persist the signed playback stream URL.
    func youtubeShareURL(at time: TimeInterval) -> URL? {
        guard YouTubeVideoLink.videoID(from: id, allowBareID: true) != nil,
              time.isFinite else { return nil }
        let seconds = Int(min(max(0, time), Double(Int32.max)))
        return URL(string: "https://youtu.be/\(id)?t=\(seconds)")
    }

    func replacingTitle(with title: String) -> Video {
        Video(
            id: id, title: title, channelID: channelID, channelName: channelName,
            channelThumbnailURL: channelThumbnailURL, thumbnailURL: thumbnailURL,
            duration: duration, viewCount: viewCount, publishedAt: publishedAt,
            publishedRelative: publishedRelative, descriptionSnippet: descriptionSnippet,
            isLive: isLive, isShort: isShort
        )
    }

    func withChannelThumbnailURL(_ url: URL) -> Video {
        Video(
            id: id, title: title, channelID: channelID, channelName: channelName,
            channelThumbnailURL: url, thumbnailURL: thumbnailURL,
            duration: duration, viewCount: viewCount, publishedAt: publishedAt,
            publishedRelative: publishedRelative, descriptionSnippet: descriptionSnippet,
            isLive: isLive, isShort: isShort
        )
    }

    func withViewCount(_ count: Int) -> Video {
        Video(
            id: id, title: title, channelID: channelID, channelName: channelName,
            channelThumbnailURL: channelThumbnailURL, thumbnailURL: thumbnailURL,
            duration: duration, viewCount: count, publishedAt: publishedAt,
            publishedRelative: publishedRelative, descriptionSnippet: descriptionSnippet,
            isLive: isLive, isShort: isShort
        )
    }

    func markedLive() -> Video {
        Video(
            id: id, title: title, channelID: channelID, channelName: channelName,
            channelThumbnailURL: channelThumbnailURL, thumbnailURL: thumbnailURL,
            duration: duration, viewCount: viewCount, publishedAt: publishedAt,
            publishedRelative: publishedRelative, descriptionSnippet: descriptionSnippet,
            isLive: true, isShort: isShort
        )
    }

    /// Feed entries reconstruct an approximate upload date from the relative text received at
    /// refresh time. Render that date against the current clock so cached ages keep advancing.
    func publishedText(relativeTo now: Date) -> String? {
        guard let publishedAt else { return publishedRelative }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .numeric
        formatter.unitsStyle = .full
        return formatter.localizedString(for: min(publishedAt, now), relativeTo: now)
    }

    var durationString: String {
        if isLive { return "LIVE" }
        guard let duration else { return "" }
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Approximate upload date for YouTube surfaces that provide only relative age text.
    /// Kept separate from `publishedAt` so a saved relative string is never mistaken for an exact date.
    func estimatedPublishedAt(relativeTo now: Date) -> Date? {
        if let publishedAt { return publishedAt }
        return Self.estimatedPublishedAt(from: publishedRelative, relativeTo: now)
    }

    static func estimatedPublishedAt(from relativeText: String?, relativeTo now: Date) -> Date? {
        guard let text = relativeText?.lowercased(),
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

    /// Compact human-readable view-count string (e.g. "1.2M views", "856 views"). Empty when the
    /// API didn't return a count, so callers can hide the label entirely.
    var viewCountString: String {
        guard let viewCount, viewCount > 0 else { return "" }
        if viewCount >= 1_000_000_000 {
            return "\(trim(Double(viewCount) / 1_000_000_000))B views"
        }
        if viewCount >= 1_000_000 {
            return "\(trim(Double(viewCount) / 1_000_000))M views"
        }
        if viewCount >= 1_000 {
            return "\(trim(Double(viewCount) / 1_000))K views"
        }
        return "\(viewCount) views"
    }

    private func trim(_ value: Double) -> String {
        // Drop the decimal when whole, otherwise show one digit ("1.2", "12").
        if value >= 100 || value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
