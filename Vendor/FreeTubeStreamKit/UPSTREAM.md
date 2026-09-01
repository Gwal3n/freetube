# FreeTubeStreamKit provenance

This is a source snapshot of
[`alexeichhorn/YouTubeKit`](https://github.com/alexeichhorn/YouTubeKit) release
`0.4.9` (`e5b7d0396ce12bf3444f0d209e8436c83373b7af`), with only the Swift package,
product, and target names changed to `FreeTubeStreamKit`.

The rename lets FreeTube use this stream extractor alongside the unrelated
`b5i/YouTubeKit` package, which exports the same package and module name and is
still used by the app's feeds, account, and metadata services.

Source-level changes:

- Two force unwraps removed and cipher solver output redacted from error logs,
  so the dependency follows FreeTube's production-safety and signed-URL rules.
- `PlayerContextCache.swift` (new) plus the `playerContext` / `loadPlayerContext`
  rework in `YouTube.swift`. Upstream caches only the player *script source*, and
  re-derives the script URL, signature timestamp, and `ytcfg` per `YouTube`
  instance — meaning a 1–2 MB watch-page download and two regex scans over the
  multi-megabyte script before every playback. None of those values are
  video-specific, so they are now shared process-wide behind a 6-hour TTL, with
  invalidation on signature-deciphering failure. This also replaced a force
  unwrap of `URL(string:)` with a thrown `YouTubeKitError.extractError`.
- `Extraction.YtCfg` and its nested types gained `Sendable` so the cache can
  return a decoded config across its actor boundary.

When re-pulling upstream, reapply these rather than discarding them; the caching
change is the difference between ~2s and ~0.3s per playback resolution.

The upstream MIT license is preserved in `LICENSE`. The remote extraction
method is intentionally not used by FreeTube; playback requests local
extraction only.
