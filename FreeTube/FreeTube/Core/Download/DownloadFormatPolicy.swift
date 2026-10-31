import Foundation

/// Format choices shared by the native fallback and yt-dlp compatibility download paths.
@available(iOS 17.0, *)
enum DownloadFormatPolicy {
    /// Keeps the compatibility downloader's client and ffmpeg policy in one place.
    static func youtubeDLArguments(
        video: Video, formatString: String, outputTemplate: String, concurrentFragments: Int
    ) -> [String] {
        // yt-dlp argv. We force mp4 output, point `-o` at our canonical Downloads/<id>.mp4 path,
        // skip writing playlist info, and feed the cleanest possible argument set. The package's
        // global yt_dlp(argv:) routes through Python and intercepts subprocess.Popen for ffmpeg/ffprobe,
        // so the in-tree FFmpegSupport library handles muxing transparently.
        //
        // SecurityHardening configures embedded Python's SSL_CERT_FILE to the bundled Mozilla
        // CA roots before the first yt-dlp run. Keep certificate verification enabled.
        //
        // **No `--cookies` flag** — counter-intuitive, but yt-dlp's safety check
        // ("Skipping client X since it does not support cookies") removes the `tv_simply`,
        // `ios`, and `android_vr` clients from the fallback chain whenever a cookies file is
        // present. Those are exactly the clients that give us the broadest format coverage on
        // PoT-locked content. With cookies the surviving clients (`web_creator`, `mweb`)
        // honestly report "No video formats found" — the bottleneck was never cookie auth, it
        // was the JS-runtime-less n-cipher (CLAUDE.md §15.4). The earlier cookie-file experiment
        // was removed so session credentials can never be materialized as plaintext temporary data.
        return [
            "https://www.youtube.com/watch?v=\(video.id)",
            "-f", formatString,
            "-o", outputTemplate,
            "--no-playlist",
            "--no-progress",
            // **Player-client fallback chain.** Try several anonymous client profiles so yt-dlp
            // can retain valid HLS/progressive fallbacks when the native resolver fails.
            //
            // `player_client=…` — explicit list of YouTube player profiles to try, in fallback
            // order. The default yt-dlp list without a JS runtime is so narrow it commonly
            // hits "This video is not available" on kids / region-locked / age-gated videos.
            // We try clients with different PoT requirements:
            //   - `tv_simply` (TVHTML5 simply-embedded-player) — broadest format coverage.
            //   - `tv_embedded` — TV embedded player, often exempt from PoT enforcement.
            //   - `web_creator` — creator-mode profile, also frequently PoT-exempt.
            //   - `mweb` — mobile web, broad coverage including kids content.
            //   - `web_safari` — desktop Safari, useful for live + premium content.
            //   - `ios` — native iOS app profile.
            //   - `android_vr` — last-resort fallback (was the only default).
            //
            // Do not opt into `formats=missing_pot`. Those entries are retained for diagnostics,
            // not made downloadable: the current device log proves yt-dlp selects one and then
            // receives HTTP 403. They also polluted the Link picker with severely throttled URLs.
            "--extractor-args",
            "youtube:player_client=tv_simply,tv_embedded,web_creator,mweb,web_safari,ios,android_vr",
            // **Concurrent fragment downloads.** For HLS/DASH streams yt-dlp downloads each
            // chunk sequentially by default — bumping this lets it fetch N fragments at once
            // over the same HTTP/2 connection. Doesn't change the total bytes pulled but cuts
            // wall-clock time, and is the closest thing to "parallel downloads" we can do
            // (Python/CPython requires single-thread interpreter access, so we can't run two
            // yt-dlp invocations side-by-side).
            //
            // Value is user-controlled via `UserPreferences.concurrentFragments`. We clamp here
            // as a defence-in-depth — `@AppStorage` can technically be poked to any Int.
            "--concurrent-fragments", "\(max(1, min(16, concurrentFragments)))",
            // Belt-and-braces: point yt-dlp at a nonexistent ffmpeg so even if some edge case tries
            // to add the merger postprocessor, it fails-fast at probe time and yt-dlp skips it
            // instead of hanging in `Popen.communicate`. Our serialized Swift-side FFmpeg mux is
            // the canonical join step now.
            "--ffmpeg-location", "/dev/null/no-ffmpeg"
        ]
    }

    /// Picks the highest-resolution progressive (single-file, both-tracks) format whose height
    /// is within the user's quality cap. nil if YouTube didn't return any combined stream.
    static func pickBestProgressive(formats: [VideoFormat], maxHeight: Int) -> VideoFormat? {
        formats
            .filter { $0.containsBothTracks && $0.url != nil }
            .filter { ($0.height ?? Int.max) <= maxHeight }
            .max { ($0.height ?? 0) < ($1.height ?? 0) }
    }

    /// Highest-resolution video-only mp4 within the cap. Prefer mp4 over webm so the downstream
    /// `ffmpeg -c copy` mux works without re-encoding.
    static func pickBestVideoOnly(formats: [VideoFormat], maxHeight: Int) -> VideoFormat? {
        let candidates = formats.filter { $0.isVideoOnly && $0.url != nil && ($0.height ?? Int.max) <= maxHeight }
        let mp4s = candidates.filter { $0.mimeType.lowercased().contains("mp4") }
        let pool = mp4s.isEmpty ? candidates : mp4s
        return pool.max { ($0.height ?? 0) < ($1.height ?? 0) }
    }

    /// Highest-bitrate audio-only m4a/mp4. Same mp4-preference rule as video to keep the mux
    /// in `-c copy` territory.
    static func pickBestAudioOnly(formats: [VideoFormat]) -> VideoFormat? {
        let candidates = formats.filter { $0.isAudioOnly && $0.url != nil }
        let mp4s = candidates.filter { $0.mimeType.lowercased().contains("mp4") || $0.mimeType.lowercased().contains("m4a") }
        let pool = mp4s.isEmpty ? candidates : mp4s
        return pool.max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
    }

    static func targetHeight(for quality: VideoQuality) -> Int {
        // Reuse the existing `heightCap` so the format selector matches yt-dlp's argv logic.
        // `audioOnly` → 0 isn't useful for video downloads, fall back to a reasonable cap.
        let cap = quality.heightCap ?? 1080
        return cap > 0 ? cap : 1080
    }

    /// Builds a yt-dlp `-f` format string honoring the user's quality preference.
    ///
    /// Selects separate MP4 video and M4A audio streams so our serialized Swift-side ffmpeg runner
    /// can mux them. Avoid mixing `/` and `,` without grouping: yt-dlp parsed the old expression as
    /// progressive itag 18 *plus* audio itag 140, downloading redundant audio and obscuring errors.
    ///
    /// We use `,` (download as separate files) instead of `+` (yt-dlp's merger) because yt-dlp's
    /// ffmpeg invocation hangs on iOS — see `muxToDestination` for the Swift-side replacement.
    static func formatString(for quality: VideoQuality) -> String {
        if quality == .audioOnly {
            return "bestaudio[ext=m4a]/bestaudio"
        }
        if let cap = quality.heightCap, cap > 0 {
            // Prefer native-friendly MP4/M4A, but fall back independently to whatever video-only
            // and audio-only formats yt-dlp actually retained after its PoToken filtering.
            return "(bestvideo[height<=\(cap)][ext=mp4]/bestvideo[height<=\(cap)],bestaudio[ext=m4a]/bestaudio)/best[height<=\(cap)][ext=mp4]/best[height<=\(cap)]"
        }
        return "(bestvideo[height<=1080][ext=mp4]/bestvideo[height<=1080],bestaudio[ext=m4a]/bestaudio)/best[height<=1080][ext=mp4]/best[height<=1080]"
    }
}
