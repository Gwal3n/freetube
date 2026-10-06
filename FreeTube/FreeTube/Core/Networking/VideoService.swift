import Foundation
import OSLog
import YouTubeKit

struct VideoInfo: Sendable {
    let video: Video
    let descriptionText: String?
    let descriptionParts: [VideoDescriptionPart]
    let likeCount: Int?
    let isLikedByUser: Bool
    let isDislikedByUser: Bool
    let recommended: [Video]
    let recommendedContinuationToken: String?
    let viewCountText: String?
    let uploadDateText: String?
    let chapters: [VideoChapter]
    let captionTracks: [VideoCaptionTrack]
    let storyboard: VideoStoryboard?
    /// Initial token and availability extracted from the same MoreVideoInfosResponse as details.
    /// Keeping them here lets background prefetch avoid issuing that response twice.
    let commentsContinuationToken: String?
    let commentsCountText: String?
    let commentsAvailability: CommentThread.Availability
    /// YouTube's own comments-entry teaser. This is an excerpt only: the response does not expose
    /// its comment ID or author name, so consumers must not model it as a complete `Comment`.
    let teaserCommentText: String?
    /// The HLS playlist URL (if available). Per `VideoInfosResponse` docs, this URL is consumable by
    /// `AVPlayer` directly. Prefer it over per-format URLs unless a specific quality is required.
    let streamingURL: URL?
    /// Formats already provided by `VideoInfosResponse` — combined audio+video streams (in `defaultFormats`)
    /// plus adaptive audio-only/video-only streams (in `downloadFormats`). These come from the iOS-client
    /// player endpoint and have direct URLs (no signature cipher), so they work without the player-JS scrape
    /// that `VideoInfosWithDownloadFormatsResponse` requires.
    let formats: [VideoFormat]
}

struct VideoInfoWithFormats: Sendable {
    let info: VideoInfo
    let formats: [VideoFormat]
}

struct RecommendedVideosPage: Sendable {
    let videos: [Video]
    let continuationToken: String?
}

protocol VideoServicing: Sendable {
    func fetchInfo(id: String) async throws -> VideoInfo
    func fetchInfoWithFormats(id: String) async throws -> VideoInfoWithFormats
    func fetchMoreInfo(id: String) async throws -> VideoInfo
    func fetchCaptionCues(track: VideoCaptionTrack) async throws -> [VideoCaptionCue]
    func fetchRecommendedVideos(continuation: String) async throws -> RecommendedVideosPage
    /// Alternate fetch using the `TVHTML5_SIMPLY_EMBEDDED_PLAYER` client — same response shape
    /// as `fetchInfo`, but the returned per-format URLs aren't PoT-protected. Used by the resolver
    /// as a fallback when the iOS client gives us only PoT-locked adaptive streams.
    func fetchInfoViaTVHTML5(id: String) async throws -> VideoInfo
}

/// Wraps `VideoInfosResponse`, `VideoInfosWithDownloadFormatsResponse`, `MoreVideoInfosResponse`.
final class VideoService: VideoServicing {
    private let client: YouTubeKitClient
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "VideoService")

    nonisolated init(client: YouTubeKitClient = .shared) {
        self.client = client
    }

    func fetchInfo(id: String) async throws -> VideoInfo {
        log.info("fetchInfo[IOS] start id=\(id, privacy: .public)")
        // `VideoInfosResponse` requires a `visitorData` token. Bootstrap may not have completed yet
        // if the user taps a video immediately on launch; ensureVisitorData no-ops when one's already set.
        await client.ensureVisitorData()
        do {
            let response = try await VideoInfosResponse.sendThrowingRequest(
                youtubeModel: client.model,
                data: [.query: id]
            )
            let info = Self.videoInfo(from: response, id: id, recommended: [])
            log.info("fetchInfo[IOS] ok id=\(id, privacy: .public) hls=\(info.streamingURL != nil, privacy: .public) formats=\(info.formats.count, privacy: .public) captions=\(info.captionTracks.count, privacy: .public)")
            return info
        } catch {
            log.error("fetchInfo[IOS] FAILED id=\(id, privacy: .public): \(String(describing: error), privacy: .public)")
            throw YouTubeServiceError.network(error)
        }
    }

    func fetchInfoViaTVHTML5(id: String) async throws -> VideoInfo {
        log.info("fetchInfo[TVHTML5] start id=\(id, privacy: .public)")
        await client.ensureVisitorData()
        do {
            let response = try await VideoInfosResponse.sendThrowingRequest(
                youtubeModel: client.tvHtmlModel,
                data: [.query: id]
            )
            let info = Self.videoInfo(from: response, id: id, recommended: [])
            log.info("fetchInfo[TVHTML5] ok id=\(id, privacy: .public) hls=\(info.streamingURL != nil, privacy: .public) formats=\(info.formats.count, privacy: .public)")
            return info
        } catch {
            log.error("fetchInfo[TVHTML5] FAILED id=\(id, privacy: .public): \(String(describing: error), privacy: .public)")
            throw YouTubeServiceError.network(error)
        }
    }

    func fetchInfoWithFormats(id: String) async throws -> VideoInfoWithFormats {
        log.info("Fetching video info+formats \(id, privacy: .public)")
        do {
            let response = try await VideoInfosWithDownloadFormatsResponse.sendThrowingRequest(
                youtubeModel: client.model,
                data: [.query: id]
            )
            let info = Self.videoInfo(from: response.videoInfos, id: id, recommended: [])
            let formats = (response.defaultFormats + response.downloadFormats).map(Mappers.format(from:))
            return VideoInfoWithFormats(info: info, formats: formats)
        } catch {
            log.error("VideoInfosWithDownloadFormatsResponse failed: \(String(describing: error), privacy: .public)")
            throw YouTubeServiceError.streamExtractionFailed
        }
    }

    func fetchMoreInfo(id: String) async throws -> VideoInfo {
        log.info("Fetching more video info \(id, privacy: .public)")
        do {
            let rawResponse = try await MoreVideoInfosWithRawDescriptionResponse.sendThrowingRequest(
                youtubeModel: client.model,
                data: [.query: id]
            )
            let response = rawResponse.info
            let recommended = response.recommendedVideos.compactMap { $0 as? YTVideo }.map(Mappers.video(from:))
            let extractedDescription = rawResponse.description
            let descriptionText = extractedDescription?.text
                ?? response.videoDescription?.compactMap(\.text).joined()
            let descriptionParts = extractedDescription?.parts
                ?? Self.descriptionParts(from: response.videoDescription ?? [])
            let linkedPartCount = descriptionParts.filter { $0.action != nil }.count
            log.info("Description parsed id=\(id, privacy: .public) raw=\(extractedDescription != nil, privacy: .public) linkedParts=\(linkedPartCount, privacy: .public)")
            let video = Video(
                id: id,
                title: response.videoTitle ?? "",
                channelID: response.channel?.channelId ?? "",
                channelName: response.channel?.name ?? "",
                channelThumbnailURL: Mappers.bestThumbnailURL(response.channel?.thumbnails ?? []),
                thumbnailURL: nil,
                duration: nil,
                viewCount: nil,
                publishedAt: nil,
                descriptionSnippet: descriptionText,
                isLive: false,
                isShort: false
            )
            return VideoInfo(
                video: video,
                descriptionText: descriptionText,
                descriptionParts: descriptionParts,
                likeCount: Self.count(
                    from: response.likesCount.defaultState ?? response.likesCount.clickedState
                ),
                isLikedByUser: response.authenticatedInfos?.likeStatus == .liked,
                isDislikedByUser: response.authenticatedInfos?.likeStatus == .disliked,
                recommended: recommended,
                recommendedContinuationToken: response.recommendedVideosContinuationToken,
                viewCountText: response.viewsCount.fullViewsCount ?? response.viewsCount.shortViewsCount,
                uploadDateText: response.timePosted.postedDate ?? response.timePosted.relativePostedDate,
                chapters: Self.chapters(from: response.chapters ?? []),
                captionTracks: [],
                storyboard: nil,
                commentsContinuationToken: response.commentsContinuationToken,
                commentsCountText: response.commentsCount,
                commentsAvailability: response.commentsContinuationToken != nil || response.commentsCount != nil
                    ? .available
                    : .disabled,
                teaserCommentText: response.teaserComment.teaserText,
                streamingURL: nil,
                formats: []
            )
        } catch {
            throw YouTubeServiceError.network(error)
        }
    }

    func fetchRecommendedVideos(continuation: String) async throws -> RecommendedVideosPage {
        do {
            let response = try await MoreVideoInfosResponse.RecommendedVideosContinuation
                .sendThrowingRequest(youtubeModel: client.model, data: [.continuation: continuation])
            return RecommendedVideosPage(
                videos: response.results.compactMap { $0 as? YTVideo }.map(Mappers.video(from:)),
                continuationToken: response.continuationToken
            )
        } catch {
            throw YouTubeServiceError.network(error)
        }
    }

    /// Fetches the selected source track only on demand. The signed URL remains memory-only and
    /// the cookie-free session never persists it. JSON3 is compact; TTML matches NewPipe's
    /// preferred subtitle format when JSON3 is unavailable.
    func fetchCaptionCues(track: VideoCaptionTrack) async throws -> [VideoCaptionCue] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        for format in ["json3", "ttml"] {
            try Task.checkCancellation()
            guard var components = URLComponents(url: track.url, resolvingAgainstBaseURL: false) else {
                break
            }
            var queryItems = components.queryItems ?? []
            queryItems.removeAll { $0.name == "fmt" || $0.name == "tlang" }
            queryItems.append(URLQueryItem(name: "fmt", value: format))
            components.queryItems = queryItems
            guard let url = components.url else { break }
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 12
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                log.notice("Caption \(format, privacy: .public) response status=\(status, privacy: .public) bytes=\(data.count, privacy: .public) for \(track.id, privacy: .public)")
                guard (200..<300).contains(status), !data.isEmpty else { continue }
                let cues: [VideoCaptionCue]
                if format == "json3" {
                    let decoded = try VideoCaptionsResponse.decodeData(data: data)
                    let plainCues = Self.captionCues(from: decoded.captionParts)
                    cues = Self.captionCues(
                        plainCues,
                        applyingStylesFrom: CaptionJSON3Parser.parse(data)
                    )
                } else {
                    cues = CaptionTTMLParser.parse(data)
                }
                if !cues.isEmpty {
                    let styledCount = cues.filter {
                        $0.runs.contains(where: { $0.isItalic || $0.colorRGB != nil })
                    }.count
                    log.info("Loaded \(cues.count, privacy: .public) \(format, privacy: .public) caption cues, styled=\(styledCount, privacy: .public) for \(track.id, privacy: .public)")
                    return cues
                }
                log.notice("Caption \(format, privacy: .public) body had no usable cues for \(track.id, privacy: .public)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let nsError = error as NSError
                log.notice("Caption \(format, privacy: .public) failed for \(track.id, privacy: .public): \(nsError.domain, privacy: .public)/\(nsError.code, privacy: .public)")
            }
        }
        log.notice("No usable caption cues for track \(track.id, privacy: .public)")
        throw YouTubeServiceError.streamExtractionFailed
    }

    // MARK: - Mapping helpers

    private static func videoInfo(from response: VideoInfosResponse, id: String, recommended: [Video]) -> VideoInfo {
        let video = Video(
            id: response.videoId ?? id,
            title: response.title ?? "",
            channelID: response.channel?.channelId ?? "",
            channelName: response.channel?.name ?? "",
            channelThumbnailURL: Mappers.bestThumbnailURL(response.channel?.thumbnails ?? []),
            thumbnailURL: Mappers.bestThumbnailURL(response.thumbnails),
            duration: nil,
            viewCount: response.viewCount.flatMap { Int($0) },
            publishedAt: nil,
            descriptionSnippet: response.videoDescription,
            isLive: response.isLive ?? false,
            isShort: false
        )
        let formats = (response.defaultFormats + response.downloadFormats).map(Mappers.format(from:))
        return VideoInfo(
            video: video,
            descriptionText: response.videoDescription,
            descriptionParts: [],
            likeCount: nil,
            isLikedByUser: false,
            isDislikedByUser: false,
            recommended: recommended,
            recommendedContinuationToken: nil,
            viewCountText: nil,
            uploadDateText: nil,
            chapters: [],
            captionTracks: Self.captionTracks(from: response.captions),
            storyboard: response.storyboard.map(Self.storyboard(from:)),
            commentsContinuationToken: nil,
            commentsCountText: nil,
            commentsAvailability: .available,
            teaserCommentText: nil,
            streamingURL: response.streamingURL,
            formats: formats
        )
    }

    private static func captionTracks(from captions: [YTCaption]) -> [VideoCaptionTrack] {
        var seen = Set<String>()
        return captions.compactMap { caption in
            guard !caption.isTranslated,
                  seen.insert(caption.id).inserted else { return nil }
            return VideoCaptionTrack(
                id: caption.id,
                languageCode: caption.languageCode,
                languageName: caption.languageName,
                url: caption.url,
                isAutoGenerated: caption.isAutoGenerated
            )
        }
    }

    private static func captionCues(
        from parts: [VideoCaptionsResponse.CaptionPart]
    ) -> [VideoCaptionCue] {
        let sorted = parts
            .filter { $0.startTime.isFinite && $0.startTime >= 0 }
            .sorted { $0.startTime < $1.startTime }

        return sorted.enumerated().compactMap { index, part in
            let text = captionText(part.text)
            guard !text.isEmpty else { return nil }
            let nextStart = sorted.indices.contains(index + 1)
                ? sorted[index + 1].startTime : part.startTime + 3
            let duration = part.duration.isFinite && part.duration > 0
                ? part.duration : max(0.1, nextStart - part.startTime)
            return VideoCaptionCue(
                startTime: part.startTime,
                endTime: min(part.startTime + duration, max(nextStart, part.startTime + 0.1)),
                text: text
            )
        }
    }

    private static func captionCues(
        _ plainCues: [VideoCaptionCue],
        applyingStylesFrom styledCues: [VideoCaptionCue]
    ) -> [VideoCaptionCue] {
        // Keep b5i's known-working timing and text. Style only matching JSON3 cues, so a
        // changed or unfamiliar event shape cannot silently alter caption playback.
        guard plainCues.count == styledCues.count else { return plainCues }
        return zip(plainCues, styledCues).map { plain, styled in
            guard abs(plain.startTime - styled.startTime) < 0.05,
                  plain.text == styled.text,
                  styled.runs.contains(where: { $0.isItalic || $0.colorRGB != nil }) else {
                return plain
            }
            return VideoCaptionCue(
                startTime: plain.startTime,
                endTime: plain.endTime,
                text: plain.text,
                runs: styled.runs
            )
        }
    }

    private static func captionText(_ raw: String) -> String {
        // b5i's JSON3 path is already plain UTF-8. Its XML fallback may still carry common
        // entities on iOS, so decode them without invoking the expensive HTML importer.
        raw.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func chapters(from chapters: [MoreVideoInfosResponse.Chapter]) -> [VideoChapter] {
        var seenStartTimes = Set<Int>()
        return chapters
            .compactMap { chapter -> VideoChapter? in
                guard let startTime = chapter.startTimeSeconds,
                      startTime >= 0,
                      seenStartTimes.insert(startTime).inserted else { return nil }
                let title = chapter.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                return VideoChapter(
                    title: title?.isEmpty == false ? title ?? "Chapter" : "Chapter",
                    startTime: TimeInterval(startTime),
                    timeDescription: chapter.timeDescriptions.shortTimeDescription,
                    thumbnailURL: Mappers.bestThumbnailURL(chapter.thumbnail)
                )
            }
            .sorted { $0.startTime < $1.startTime }
    }

    private static func descriptionParts(
        from parts: [MoreVideoInfosResponse.YouTubeDescriptionPart]
    ) -> [VideoDescriptionPart] {
        var mapped: [VideoDescriptionPart] = []
        for part in parts {
            guard let text = part.text, !text.isEmpty else { continue }
            let action: VideoDescriptionPart.Action?
            if let seconds = VideoDescriptionExtractor.timestampSeconds(from: text) {
                action = .seek(seconds)
            } else {
                switch part.role {
                case .link(let url): action = .externalURL(VideoDescriptionExtractor.unwrappedRedirect(url))
                case .chapter(let seconds): action = .seek(TimeInterval(seconds))
                case .video(let id): action = .video(id)
                case .channel(let id): action = .channel(id)
                case .playlist(let id): action = .playlist(id)
                default: action = nil
                }
            }
            mapped.append(VideoDescriptionPart(text: text, action: action))
        }
        return repairingSplitTimestamps(in: mapped)
    }

    /// YouTube occasionally splits the first digit of a timestamp into the preceding plain-text
    /// run (for example `"1" + "0:42"`). Join that digit run back onto the linked timestamp so
    /// both its blue range and its seek destination describe the complete `10:42` value.
    private static func repairingSplitTimestamps(
        in parts: [VideoDescriptionPart]
    ) -> [VideoDescriptionPart] {
        var repaired: [VideoDescriptionPart] = []
        for part in parts {
            guard case .seek = part.action,
                  part.text.split(separator: ":").count == 2,
                  let previous = repaired.last,
                  previous.action == nil else {
                repaired.append(part)
                continue
            }

            let trailingDigits = previous.text.reversed().prefix(while: \.isNumber).reversed()
            guard !trailingDigits.isEmpty else {
                repaired.append(part)
                continue
            }

            let combinedText = String(trailingDigits) + part.text
            guard let seconds = VideoDescriptionExtractor.timestampSeconds(from: combinedText) else {
                repaired.append(part)
                continue
            }

            repaired.removeLast()
            let prefix = String(previous.text.dropLast(trailingDigits.count))
            if !prefix.isEmpty {
                repaired.append(VideoDescriptionPart(text: prefix, action: nil))
            }
            repaired.append(VideoDescriptionPart(text: combinedText, action: .seek(seconds)))
        }
        return repaired
    }

    /// YouTube commonly returns compact counts (`48K`, `1.2M`) rather than integer strings.
    private static func count(from text: String?) -> Int? {
        guard var value = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: ",", with: "")
        let numberText = value.prefix { $0.isNumber || $0 == "." }
        guard !numberText.isEmpty else { return nil }
        let suffix = value.dropFirst(numberText.count)
            .first(where: { !$0.isWhitespace })
        let multiplier: Double
        if suffix == "k" {
            multiplier = 1_000
        } else if suffix == "m" {
            multiplier = 1_000_000
        } else if suffix == "b" {
            multiplier = 1_000_000_000
        } else {
            multiplier = 1
        }
        guard let number = Double(numberText), number >= 0 else { return nil }
        return Int((number * multiplier).rounded())
    }

    private static func storyboard(from storyboard: YTStoryboard) -> VideoStoryboard {
        VideoStoryboard { time, duration, maximumWidth, maximumHeight in
            guard let tile = storyboard.tile(
                at: time,
                duration: duration,
                maximumWidth: maximumWidth,
                maximumHeight: maximumHeight
            ) else { return nil }
            return VideoStoryboard.Tile(
                url: tile.url,
                column: tile.column,
                row: tile.row,
                columns: tile.level.columns,
                rows: tile.level.rows,
                width: tile.level.width,
                height: tile.level.height
            )
        }
    }
}
