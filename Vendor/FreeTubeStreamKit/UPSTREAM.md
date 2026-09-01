# FreeTubeStreamKit provenance

This is a source snapshot of
[`alexeichhorn/YouTubeKit`](https://github.com/alexeichhorn/YouTubeKit) release
`0.4.9` (`e5b7d0396ce12bf3444f0d209e8436c83373b7af`), with only the Swift package,
product, and target names changed to `FreeTubeStreamKit`.

The rename lets FreeTube use this stream extractor alongside the unrelated
`b5i/YouTubeKit` package, which exports the same package and module name and is
still used by the app's feeds, account, and metadata services.

The only source-level changes remove two force unwraps and redact cipher solver
output from error logs so the dependency follows FreeTube's production-safety
and signed-URL handling rules.

The upstream MIT license is preserved in `LICENSE`. The remote extraction
method is intentionally not used by FreeTube; playback requests local
extraction only.
