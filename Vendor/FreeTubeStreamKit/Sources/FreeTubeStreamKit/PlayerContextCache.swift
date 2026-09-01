//
//  PlayerContextCache.swift
//  FreeTubeStreamKit
//
//  FreeTube addition — see UPSTREAM.md.
//

import Foundation

/// Process-wide cache for the values that describe YouTube's *current player*, as opposed to any
/// particular video: the player script URL, its source, the signature timestamp derived from it,
/// and the `ytcfg` blob scraped from the watch page alongside it.
///
/// None of these are video-specific. They change only when YouTube rotates `player.js`, which
/// happens on the order of once every few weeks. Upstream cached only the script *source*, and only
/// between calls, so every `YouTube` instance still re-derived the URL, timestamp, and config from
/// a freshly downloaded watch page. That put a 1–2 MB HTML download plus two regex scans over the
/// multi-megabyte script in front of every single playback — roughly 1.5s that the HLS manifest
/// path (which needs none of these values) was paying for nothing.
///
/// Entries expire after `ttl` so a rotation is picked up without relaunching, and ``invalidate()``
/// drops them immediately when signature deciphering fails against what turned out to be a stale
/// script.
///
/// - Note: A cold cache filled by two concurrent resolutions will load twice. That matches the
///   previous behaviour and can't happen today because playback resolution is serialised per
///   player; revisit with in-flight coalescing if speculative prefetching lands.
@available(iOS 13.0, watchOS 6.0, tvOS 13.0, macOS 10.15, *)
actor PlayerContextCache {

    static let shared = PlayerContextCache()

    struct Context: Sendable {
        let jsURL: URL
        let js: String
        let signatureTimestamp: Int?
        let ytcfg: Extraction.YtCfg
    }

    private var stored: (context: Context, at: Date)?
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 6 * 60 * 60) {
        self.ttl = ttl
    }

    /// The cached context, or `nil` when nothing is stored or the entry has aged out.
    var current: Context? {
        guard let stored, Date().timeIntervalSince(stored.at) < ttl else { return nil }
        return stored.context
    }

    func store(_ context: Context) {
        stored = (context, Date())
    }

    func invalidate() {
        stored = nil
    }
}
