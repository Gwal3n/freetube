import Foundation
import YouTubeKit

/// Maps YouTubeKit response types into the app's domain models. Lives in `Core/Networking/` per
/// CLAUDE.md §6 — services use these helpers; nothing outside this folder should see YouTubeKit types.
enum Mappers {

    // MARK: - Thumbnails

    /// Largest thumbnail (last in the array per YouTubeKit's sort order).
    static func bestThumbnailURL(_ thumbnails: [YTThumbnail]) -> URL? {
        thumbnails.last?.url
    }

    // MARK: - Videos

    static func video(from yt: YTVideo) -> Video {
        // Parse display timeLength — YouTubeKit rejects three-part stamps like "1:02:03".
        let duration = Self.duration(from: yt.timeLength)
        // Empty Shorts lockup thumbs → canonical hqdefault CDN URL.
        let thumb = bestThumbnailURL(yt.thumbnails) ?? canonicalThumbnailURL(for: yt.videoId)
        return Video(
            id: yt.videoId,
            title: yt.title ?? "",
            channelID: yt.channel?.channelId ?? "",
            // Playlist lockups sometimes put a view-count label in the channel slot.
            channelName: channelName(from: yt.channel?.name),
            channelThumbnailURL: bestThumbnailURL(yt.channel?.thumbnails ?? []),
            thumbnailURL: thumb,
            duration: duration,
            viewCount: parseViewCount(yt.viewCount),
            publishedAt: nil,
            publishedRelative: yt.timePosted,
            descriptionSnippet: nil,
            isLive: yt.timeLength?.localizedCaseInsensitiveCompare("live") == .orderedSame,
            isShort: false
        )
    }

    static func duration(from timeLength: String?) -> TimeInterval? {
        guard let timeLength else { return nil }
        let parts = timeLength.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var seconds = 0
        for (index, part) in parts.enumerated() {
            guard let value = Int(part), value >= 0,
                  (index == 0 || value < 60),
                  seconds <= (Int.max - value) / 60 else { return nil }
            seconds = seconds * 60 + value
        }
        return seconds > 0 ? TimeInterval(seconds) : nil
    }

    static func channelName(from raw: String?) -> String {
        guard let raw else { return "" }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = name.lowercased()
        if lower.hasSuffix(" views"), name.first?.isNumber == true {
            return ""
        }
        return name
    }

    /// Canonical YouTube CDN thumbnail. `hqdefault` is 480×360 and is always available for any
    /// public video — used as a fallback when YouTubeKit doesn't populate the thumbnails array.
    static func canonicalThumbnailURL(for videoID: String) -> URL? {
        URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")
    }

    private static func parseViewCount(_ text: String?) -> Int? {
        guard let text else { return nil }
        let lower = text.lowercased()
        // Quick path: pure digits with optional separators ("1,234,567").
        let digits = text.unicodeScalars.filter(CharacterSet.decimalDigits.contains).map(Character.init)
        if let value = Int(String(digits)), !lower.contains("k"), !lower.contains("m"), !lower.contains("b") {
            return value
        }
        // Short-form path ("1.2M views", "856K"): parse the leading number then apply suffix.
        let trimmed = lower
            .replacingOccurrences(of: "views", with: "")
            .replacingOccurrences(of: "view", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return nil }
        let multiplier: Double
        switch last {
        case "k": multiplier = 1_000
        case "m": multiplier = 1_000_000
        case "b": multiplier = 1_000_000_000
        default:
            return Int(String(digits))
        }
        let number = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
        guard let value = Double(number) else { return nil }
        return Int(value * multiplier)
    }

    // MARK: - Channels

    static func channel(from yt: YTChannel) -> Channel {
        Channel(
            id: yt.channelId,
            name: yt.name ?? "",
            handle: yt.handle,
            thumbnailURL: bestThumbnailURL(yt.thumbnails),
            bannerURL: nil,
            subscriberCount: parseAbbreviatedCount(yt.subscriberCount),
            videoCount: parseAbbreviatedCount(yt.videoCount),
            isSubscribed: false,
            descriptionText: nil
        )
    }

    /// Parses abbreviated count strings (`"1.2M subscribers"`, `"5 videos"`, bare numbers).
    /// Strip plural suffixes first so `"subscribers"` does not leave a dangling `"s"`.
    static func parseAbbreviatedCount(_ raw: String?) -> Int? {
        guard let raw, !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        let suffixes = [
            "subscribers", "subscriber",
            "views", "view",
            "videos", "video",
            "playlists", "playlist",
            "items", "item",
            "channels", "channel"
        ]
        var stripped = lower
        for suffix in suffixes {
            stripped = stripped.replacingOccurrences(of: suffix, with: "")
        }
        stripped = stripped.trimmingCharacters(in: .whitespaces)

        // Some locales emit non-breaking spaces in counts ("1 234"); normalise everything
        // whitespace-like to plain space, then drop spaces entirely after we've handled the
        // suffix.
        stripped = stripped.replacingOccurrences(of: "\u{00A0}", with: " ")

        guard let last = stripped.last else { return nil }
        let multiplier: Double
        switch last {
        case "k": multiplier = 1_000
        case "m": multiplier = 1_000_000
        case "b": multiplier = 1_000_000_000
        default:
            // Plain digit string with separators — strip commas, dots-as-thousands, and any
            // remaining whitespace, then convert.
            let digits = stripped
                .replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: " ", with: "")
            return Int(digits)
        }
        let number = stripped.dropLast().trimmingCharacters(in: .whitespaces)
        guard let value = Double(number) else { return nil }
        return Int(value * multiplier)
    }

    static func channel(from yt: YTLittleChannelInfos) -> Channel {
        Channel(
            id: yt.channelId,
            name: yt.name ?? "",
            handle: nil,
            thumbnailURL: bestThumbnailURL(yt.thumbnails),
            bannerURL: nil,
            subscriberCount: nil,
            videoCount: nil,
            isSubscribed: false,
            descriptionText: nil
        )
    }

    // MARK: - Playlists

    static func playlist(from yt: YTPlaylist) -> Playlist {
        Playlist(
            id: yt.playlistId,
            title: yt.title ?? "",
            channelID: yt.channel?.channelId,
            channelName: yt.channel?.name,
            thumbnailURL: bestThumbnailURL(yt.thumbnails),
            videoCount: parseAbbreviatedCount(yt.videoCount),
            descriptionText: nil,
            isOwnedByUser: false
        )
    }

    // MARK: - Comments

    static func comment(from yt: YTComment, authorAvatarURL: URL? = nil) -> Comment {
        let likeCount = Int(yt.likesCount?.filter(\.isNumber) ?? "") ?? 0
        return Comment(
            id: yt.commentIdentifier,
            authorName: yt.sender?.name ?? "",
            authorChannelID: yt.sender?.channelId,
            authorThumbnailURL: bestThumbnailURL(yt.sender?.thumbnails ?? []) ?? authorAvatarURL,
            bodyText: yt.text,
            likeCount: likeCount,
            publishedRelative: yt.timePosted ?? "",
            replyCount: Int(yt.totalRepliesNumber?.filter(\.isNumber) ?? "") ?? yt.replies.count,
            replyContinuationToken: yt.actionsParams[.repliesContinuation]
        )
    }

    // MARK: - Formats

    static func format(from yt: any DownloadFormat) -> VideoFormat {
        let mime = yt.mimeType ?? ""
        if let video = yt as? VideoDownloadFormat {
            return VideoFormat(
                id: "\(video.height ?? 0)x\(video.width ?? 0)-\(video.averageBitrate ?? 0)",
                url: video.url,
                mimeType: mime,
                height: video.height,
                width: video.width,
                bitrate: video.averageBitrate,
                audioSampleRate: nil,
                isVideoOnly: true,
                isAudioOnly: false,
                containsBothTracks: false
            )
        }
        if let audio = yt as? AudioOnlyFormat {
            return VideoFormat(
                id: "audio-\(audio.averageBitrate ?? 0)",
                url: audio.url,
                mimeType: mime,
                height: nil,
                width: nil,
                bitrate: audio.averageBitrate,
                audioSampleRate: audio.audioSampleRate,
                isVideoOnly: false,
                isAudioOnly: true,
                containsBothTracks: false
            )
        }
        return VideoFormat(
            id: UUID().uuidString,
            url: yt.url,
            mimeType: mime,
            height: nil,
            width: nil,
            bitrate: yt.averageBitrate,
            audioSampleRate: nil,
            isVideoOnly: false,
            isAudioOnly: false,
            containsBothTracks: true
        )
    }
}
