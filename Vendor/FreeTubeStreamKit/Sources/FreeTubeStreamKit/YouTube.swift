//
//  YouTube.swift
//  YouTubeKit
//
//  Created by Alexander Eichhorn on 04.09.21.
//

import Foundation
@preconcurrency import os.log

@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
public class YouTube {

    /// Player-scoped values for this instance. Backed by ``PlayerContextCache`` so the watch-page
    /// download and script scans they require are paid once per player rotation rather than once
    /// per video.
    private var _playerContext: PlayerContextCache.Context?

    private var _videoInfos: [InnerTube.VideoInfo]?

    private var _watchHTML: String?
    private var _embedHTML: String?
    private var playerConfigArgs: [String: Any]?
    private var _ageRestricted: Bool?

    private var _fmtStreams: [Stream]?

    private var initialData: Data?

    /// Represents a property that provides metadata for a YouTube video.
    ///
    /// This property allows you to retrieve metadata for a YouTube video asynchronously.
    /// - Note: Currently doesn't respect `method` set. It always uses `.local`
    public var metadata: YouTubeMetadata? {
        get async throws {
            return .metadata(from: try await videoDetails)
        }
    }

    public let videoID: String

    var watchURL: URL {
        URL(string: "https://youtube.com/watch?v=\(videoID)")!
    }

    private var extendedWatchURL: URL {
        URL(string: "https://youtube.com/watch?v=\(videoID)&bpctr=9999999999&has_verified=1")!
    }

    var embedURL: URL {
        URL(string: "https://www.youtube.com/embed/\(videoID)")!
    }

    // stream monostate TODO

    private var author: String?
    private var title: String?
    private var publishDate: String?

    let useOAuth: Bool
    let allowOAuthCache: Bool

    let methods: [ExtractionMethod]

    private let log = OSLog(YouTube.self)

    /// - parameter methods: Methods used to extract streams from the video - ordered by priority (Default: `local` on iOS, macOS, tvOS, visionOS; `remote` on watchOS)
    public init(videoID: String, proxies: [String: URL] = [:], useOAuth: Bool = false, allowOAuthCache: Bool = false, methods: [ExtractionMethod] = .default) {
        self.videoID = videoID
        self.useOAuth = useOAuth
        self.allowOAuthCache = allowOAuthCache
        // TODO: install proxies if needed

        if methods.isEmpty {
#if canImport(JavaScriptCore)
            self.methods = [.local]
#else
            self.methods = [.remote]
#endif
        } else {
            self.methods = methods.removeDuplicates()
        }
    }

    /// - parameter methods: Methods used to extract streams from the video - ordered by priority (Default: `local` on iOS, macOS, tvOS, visionOS; `remote` on watchOS)
    public convenience init(url: URL, proxies: [String: URL] = [:], useOAuth: Bool = false, allowOAuthCache: Bool = false, methods: [ExtractionMethod] = .default) {
        let videoID = Extraction.extractVideoID(from: url.absoluteString) ?? ""
        self.init(videoID: videoID, proxies: proxies, useOAuth: useOAuth, allowOAuthCache: allowOAuthCache, methods: methods)
    }


    private var watchHTML: String {
        get async throws {
            if let cached = _watchHTML {
                return cached
            }
            var request = URLRequest(url: extendedWatchURL)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en", forHTTPHeaderField: "accept-language")
            request.httpShouldHandleCookies = false
            let (data, _) = try await URLSession.shared.data(for: request)
            _watchHTML = String(data: data, encoding: .utf8) ?? ""
            return _watchHTML!
        }
    }

    private var embedHTML: String {
        get async throws {
            if let cached = _embedHTML {
                return cached
            }
            var request = URLRequest(url: embedURL)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("en-US,en", forHTTPHeaderField: "accept-language")
            request.setValue("https://www.reddit.com/", forHTTPHeaderField: "Referer")
            request.httpShouldHandleCookies = false
            let (data, _) = try await URLSession.shared.data(for: request)
            _embedHTML = String(data: data, encoding: .utf8) ?? ""
            return _embedHTML!
        }
    }


    /// check whether the video is available
    public func checkAvailability() async throws {
        let (status, messages) = try Extraction.playabilityStatus(watchHTML: await watchHTML)

        for reason in messages {
            switch status {
            case .unplayable:
                if reason?.starts(with: "Join this channel to get access to members-only content") ?? false { // TODO: original compared to tuple
                    throw YouTubeKitError.membersOnly
                }
            case .loginRequired:
                if reason.map({ $0.starts(with: "This is a private video") || $0.starts(with: "This video is private") }) ?? false { // TODO: original: reason == ["This is a private video. ", "Please sign in to verify that you may see it."] {
                    throw YouTubeKitError.videoPrivate
                }
            case .error:
                throw YouTubeKitError.videoUnavailable
            case .liveStream:
                let streamingData = try await videoInfos.map { $0.streamingData }
                if streamingData.allSatisfy({ $0?.hlsManifestUrl == nil }) {
                    throw YouTubeKitError.liveStreamError
                }
                continue
            case .ok, .none:
                continue
            }
        }
    }

    public var ageRestricted: Bool {
        get async throws {
            if let cached = _ageRestricted {
                return cached
            }

            _ageRestricted = try await Extraction.isAgeRestricted(watchHTML: watchHTML)
            return _ageRestricted!
        }
    }

    /// The player script URL, its source, the signature timestamp, and the watch-page `ytcfg`.
    ///
    /// Served from ``PlayerContextCache`` whenever a fresh entry exists, which is the common case:
    /// none of these values depend on the video being played. On a hit this instance never touches
    /// ``watchHTML`` at all, which is what removes the per-playback 1–2 MB page download.
    private var playerContext: PlayerContextCache.Context {
        get async throws {
            if let cached = _playerContext {
                return cached
            }
            if let shared = await PlayerContextCache.shared.current {
                _playerContext = shared
                return shared
            }
            let context = try await loadPlayerContext()
            await PlayerContextCache.shared.store(context)
            _playerContext = context
            return context
        }
    }

    /// Derives a fresh player context from the watch page. Only runs on a cache miss.
    ///
    /// - Note: the age-restricted branch reads the player URL from the embed page instead, because
    ///   an age-gated watch page may not carry the player config. A context cached from an ordinary
    ///   video is still reused for age-restricted ones — YouTube serves the same `base.js` to both,
    ///   and a genuine mismatch surfaces as a deciphering failure, which invalidates the cache and
    ///   retries.
    private func loadPlayerContext() async throws -> PlayerContextCache.Context {
        let playerHTML: String
        if try await ageRestricted {
            playerHTML = try await embedHTML
        } else {
            playerHTML = try await watchHTML
        }

        let jsURLString = try Extraction.jsURL(html: playerHTML)
        guard let jsURL = URL(string: jsURLString) else {
            throw YouTubeKitError.extractError
        }

        let (data, _) = try await URLSession.shared.data(from: jsURL)
        let js = String(data: data, encoding: .utf8) ?? ""
        let ytcfg = try await Extraction.extractYtCfg(from: watchHTML)

        return PlayerContextCache.Context(
            jsURL: jsURL,
            js: js,
            signatureTimestamp: Extraction.extractSignatureTimestamp(fromJS: js),
            ytcfg: ytcfg
        )
    }

    /// Drops this instance's player context and the shared one, forcing the next access to
    /// re-derive both from a freshly downloaded watch page.
    private func invalidatePlayerContext() async {
        _playerContext = nil
        await PlayerContextCache.shared.invalidate()
    }

    var jsURL: URL {
        get async throws { try await playerContext.jsURL }
    }

    var js: String {
        get async throws { try await playerContext.js }
    }

    var signatureTimestamp: Int? {
        get async throws { try await playerContext.signatureTimestamp }
    }

    var ytcfg: Extraction.YtCfg {
        get async throws { try await playerContext.ytcfg }
    }

    /// Interface to query both adaptive (DASH) and progressive streams.
    /// Returns a list of streams if they have been initialized.
    /// If the streams have not been initialized, finds all relevant streams and initializes them.
    public var streams: [Stream] {
        get async throws {
            try await checkAvailability()
            if let cached = _fmtStreams {
                return cached
            }

            let result = try await Task.retry(with: methods) { method in
                switch method {
#if canImport(JavaScriptCore)
                case .local:
                    let allStreamingData = try await self.streamingData
                    let videoInfos = try await self.videoInfos

                    var streams = [Stream]()
                    var existingITags = Set<Int>()

                    func process(streamingData: InnerTube.StreamingData, videoInfo: InnerTube.VideoInfo) async throws {

                        var streamManifest = Extraction.applyDescrambler(streamData: streamingData)

                        do {
                            try await Extraction.applySignature(streamManifest: &streamManifest, videoInfo: videoInfo, js: js)
                        } catch {
                            // Most likely the cached player script was rotated out from under us.
                            // Drop the whole context — URL, source, timestamp and config all come
                            // from the same player — and retry against a freshly derived one.
                            await self.invalidatePlayerContext()
                            try await Extraction.applySignature(streamManifest: &streamManifest, videoInfo: videoInfo, js: js)
                        }

                        // filter out dubbed audio tracks
                        streamManifest = Extraction.filterOutDubbedAudio(streamManifest: streamManifest)

                        let newStreams = streamManifest.compactMap { try? Stream(format: $0) }

                        // make sure only one stream per itag exists
                        for stream in newStreams {
                            if existingITags.insert(stream.itag.itag).inserted {
                                streams.append(stream)
                            }
                        }
                    }

                    for (streamingData, videoInfo) in zip(allStreamingData, videoInfos) {
                        try await process(streamingData: streamingData, videoInfo: videoInfo)
                    }

                    // if no progressive (audio+video) tracks were found, try to do one more call to maybe get them
                    if !streams.contains(where: { $0.includesVideoAndAudioTrack }) {
                        if let videoInfo = try? await loadAdditionalVideoInfos(forClient: .mediaConnectFrontend), let streamingData = videoInfo.streamingData {
                            os_log("Found no progressive streams. Called mediaConnectFrontend client to get additional video infos", log: log, type: .info)
                            try await process(streamingData: streamingData, videoInfo: videoInfo)
                        }
                    }

                    return streams
#endif

                case .remote(let serverURL):
                    let remoteClient = RemoteYouTubeClient(serverURL: serverURL)
                    let remoteStreams = try await remoteClient.extractStreams(forVideoID: videoID)

                    return remoteStreams.compactMap { try? Stream(remoteStream: $0) }
                }
            }

            _fmtStreams = result
            return result
        }
    }

    /// Returns a list of live streams - currently only HLS supported
    /// - Note: Currently doesn't respect `method` set. It always uses `.local`
    public var livestreams: [Livestream] {
        get async throws {
            var livestreams = [Livestream]()
            let hlsURLs = try await streamingData.compactMap { $0.hlsManifestUrl }.compactMap { URL(string: $0) }
            livestreams.append(contentsOf: hlsURLs.map { Livestream(url: $0, streamType: .hls) })
            return livestreams
        }
    }

    /// streaming data from video info
    var streamingData: [InnerTube.StreamingData] {
        get async throws {
            let streamingData = try await videoInfos.compactMap { $0.streamingData }
            if !streamingData.isEmpty {
                return streamingData
            } else {
                if let videoInfo = try? await loadAdditionalVideoInfos(forClient: .webEmbed), let streamingData = videoInfo.streamingData {
                    _videoInfos = [videoInfo]
                    return [streamingData]
                }

                try await bypassAgeGate()
                let streamingData = try await videoInfos.compactMap { $0.streamingData }
                if !streamingData.isEmpty {
                    return streamingData
                } else {
                    throw YouTubeKitError.extractError
                }
            }
        }
    }

    /// Video details from video info.
    var videoDetails: [InnerTube.VideoInfo.VideoDetails] {
        get async throws {
            try await videoInfos.compactMap { $0.videoDetails }
        }
    }

    var videoInfos: [InnerTube.VideoInfo] {
        get async throws {
            if let cached = _videoInfos {
                return cached
            }

            // try extracting video infos from watch html directly as well
            let watchVideoInfoTask = Task<InnerTube.VideoInfo?, Never> { [log] in
                do {
                    return nil //try await Extraction.getVideoInfo(fromHTML: watchHTML)  // (temporarily disabled)
                } catch let error {
                    os_log("Couldn't extract video info from main watch html: %{public}@", log: log, type: .debug, error.localizedDescription)
                    return nil
                }
            }

            let signatureTimestamp = try await signatureTimestamp
            let ytcfg = try await ytcfg

            let innertubeClients: [InnerTube.ClientType] = [.visionOS, .web]

            let results: [Result<InnerTube.VideoInfo, Error>] = await innertubeClients.concurrentMap { [videoID, useOAuth, allowOAuthCache] client in
                let innertube = InnerTube(client: client, signatureTimestamp: signatureTimestamp, ytcfg: ytcfg, useOAuth: useOAuth, allowCache: allowOAuthCache)

                do {
                    let innertubeResponse = try await innertube.player(videoID: videoID)
                    return .success(innertubeResponse)
                } catch let error {
                    return .failure(error)
                }
            }

            var videoInfos = [InnerTube.VideoInfo]()
            var errors = [Error]()

            for result in results {
                switch result {
                case .success(let innertubeResponse):
                    videoInfos.append(innertubeResponse)
                case .failure(let error):
                    errors.append(error)
                }
            }

            // append potentially extracted video info (with least priority)
            if let watchVideoInfo = await watchVideoInfoTask.value {
                videoInfos.append(watchVideoInfo)
            }

            // remove video infos with incorrect videoID
            for (i, videoInfo) in videoInfos.enumerated() where videoInfo.videoDetails?.videoId != videoID {
                os_log("Skipping player response from client %{public}i. Got player response for %{public}@ instead of %{public}@", log: log, type: .info, i, videoInfo.videoDetails?.videoId ?? "nil", videoID)
            }
            videoInfos = videoInfos.filter { $0.videoDetails?.videoId == videoID }

            if videoInfos.isEmpty {
                throw errors.first ?? YouTubeKitError.extractError
            }

            _videoInfos = videoInfos
            return videoInfos
        }
    }

    private func loadAdditionalVideoInfos(forClient client: InnerTube.ClientType) async throws -> InnerTube.VideoInfo {
        let signatureTimestamp = try await signatureTimestamp
        let ytcfg = if client == .webEmbed {
            try await Extraction.extractYtCfg(from: embedHTML)
        } else {
            try await ytcfg
        }
        let innertube = InnerTube(client: client, signatureTimestamp: signatureTimestamp, ytcfg: ytcfg, useOAuth: useOAuth, allowCache: allowOAuthCache)
        let videoInfo = try await innertube.player(videoID: videoID)

        // ignore if incorrect videoID
        if videoInfo.videoDetails?.videoId != videoID {
            os_log("Skipping player response from %{public}@ client. Got player response for %{public}@ instead of %{public}@", log: log, type: .info, client.rawValue, videoInfo.videoDetails?.videoId ?? "nil", videoID)
            throw YouTubeKitError.extractError
        }

        return videoInfo
    }

    private func bypassAgeGate() async throws {
        let signatureTimestamp = try await signatureTimestamp
        let ytcfg = try await ytcfg
        let innertube = InnerTube(client: .webCreator, signatureTimestamp: signatureTimestamp, ytcfg: ytcfg, useOAuth: useOAuth, allowCache: allowOAuthCache)
        let innertubeResponse = try await innertube.player(videoID: videoID)

        if innertubeResponse.playabilityStatus?.status == "UNPLAYABLE" || innertubeResponse.playabilityStatus?.status == "LOGIN_REQUIRED" {
            throw YouTubeKitError.videoAgeRestricted
        }

        if innertubeResponse.videoDetails?.videoId != videoID {
            os_log("Skipping player response from webCreator client. Got player response for %{public}@ instead of %{public}@", log: log, type: .info, innertubeResponse.videoDetails?.videoId ?? "nil", videoID)
            throw YouTubeKitError.extractError
        }

        _videoInfos = [innertubeResponse]
    }

    /// Interface to query both adaptive (DASH) and progressive streams.
    /*public var streams: StreamQuery {
        get async throws {
            //try await checkAvailability()
            return StreamQuery(fmtStreams: try await fmtStreams)
        }
    }*/

}
