import Foundation
import OSLog
import PythonKit
import YoutubeDL

/// Forked variant of YoutubeDL-iOS's `yt_dlp(argv:progress:log:makeTranscodeProgressBlock:)` whose
/// only structural difference is the call to `PythonJSBridge.install()` between `YtDlp` init and
/// `ydl.download`.
///
/// **Why we need this fork.** The package's `yt_dlp(...)` does, in order:
///   1. `let context = YoutubeDL()`
///   2. `let yt_dlp = try await YtDlp(context: context)` — this triggers `loadPythonModule()`
///      which calls `injectFakePopen(handler:)`, replacing `subprocess.Popen` with the package's
///      ffmpeg-only `Pop` class.
///   3. `parseOptions`, configure logger / progress, build post-processor.
///   4. `try ydl.download.throwing.dynamicallyCall(withArguments: all_urls)` — actually downloads.
///
/// To make yt-dlp's n-cipher solver succeed we need to extend `subprocess.Popen` so calls to
/// `deno`/`node` route through our `JavaScriptCore`-backed `JSEvaluator`. That extension has
/// to happen **between steps 2 and 4** — earlier and the package's `injectFakePopen` clobbers
/// us, later and yt-dlp has already given up. The package's `yt_dlp(...)` is a single async
/// block that doesn't expose a splice point, so we replicate it.
///
/// **What we drop vs the package version:**
///   - The `MyPP` post-processor that pokes `merger+ffmpeg` postprocessor_args with `-b:v`. That
///     setting is only consumed by yt-dlp's ffmpeg merger path, which we disable via
///     `--ffmpeg-location /dev/null/no-ffmpeg` (CLAUDE.md §15.3); our Swift-side `FFmpegRunner`
///     mux doesn't read it. Skipping the PP keeps this fork ~25 lines instead of 45.
///   - `context.willTranscode` — set on the `YoutubeDL` Swift class (typealiased to `Context`,
///     which is internal to the package). We can't reach it from outside anyway, and it only
///     drives transcode progress for yt-dlp's in-process ffmpeg pipeline (which is also
///     disabled). Not needed.
///
/// **Init quirk:** the package's `YtDlp.init(context:)` is internal — only the no-arg public
/// `init() async throws` (a convenience init that creates its own `Context()`) is reachable
/// from outside. We use that; the Context object is opaque to us but the bridge install only
/// needs Python state to exist, which `YtDlp()` provides via its `loadPythonModule()` call.
///
/// **What we preserve verbatim:** logger wiring, progress-hook wiring, parseOptions, the
/// `ydl.download.throwing.dynamicallyCall(withArguments: all_urls)` invocation pattern.
@available(iOS 17.0, *)
public nonisolated func freetube_yt_dlp(
    argv: [String],
    progress: @escaping @Sendable ([String: PythonObject]) -> Void,
    log: @escaping @Sendable (String, String) -> Void
) async throws {
    let bridgeLog = AppLog(subsystem: "com.leshko.freetube", category: "FreeTubeYtDlp")

    // Step 1+2 (collapsed): `YtDlp()`'s convenience init creates its own Context() internally
    // and calls `loadPythonModule()`, which initializes Python, downloads yt-dlp on first run,
    // and (critically for us) runs `injectFakePopen` — replacing `subprocess.Popen` with the
    // package's ffmpeg-only `Pop` class. After this returns we own the splice point.
    let ytdlp = try await YtDlp()

    // Splice point: now that `injectFakePopen` has run, layer our extension on top. Our
    // `_FreeTubePop` wraps the package's `Pop` (delegating ffmpeg/ffprobe) and additionally
    // routes `deno`/`node` calls through `JSEvaluator`. Idempotent across multiple
    // invocations of `freetube_yt_dlp` in the same process — the Python `_PrevPopen` capture
    // and class redefinition is harmless on repeat.
    bridgeLog.info("YtDlp ready, installing JS bridge before download")
    PythonJSBridge.install()

    // Step 3: configure options exactly as the package's `yt_dlp(...)` does, plus our
    // synthetic `js_runtimes` entry that registers our fake deno path with yt-dlp's
    // `_js_runtimes` dict. Without this, the dict stays empty and `DenoJCP.runtime_info`
    // returns `None` — bypassing the EJS path entirely no matter what else we patch.
    let (ydl_opts, all_urls) = try ytdlp.parseOptions(args: argv)
    ydl_opts["logger"] = makeLogger(name: "MyLogger", log)
    ydl_opts["progress_hooks"] = [makeProgressHook(progress)]
    ydl_opts["js_runtimes"] = PythonObject(["deno": ["path": PythonJSBridge.fakeDenoPath]])

    // Step 4: build the YoutubeDL downloader. `YtDlp.makeYoutubeDL(ydlOpts:)` is `internal` to
    // the package so we can't call it directly; we replicate it by importing the Python yt_dlp
    // module ourselves and instantiating `yt_dlp.YoutubeDL(opts)`. Same result, same object.
    let yt_dlp_module = try Python.attemptImport("yt_dlp")
    let ydl = yt_dlp_module.YoutubeDL(ydl_opts)

    // Step 5: actually run. yt-dlp's extractor chain will now find `deno` via our shim and
    // succeed at n-cipher solving — assuming the JS function yt-dlp extracts from player.js is
    // pure ES (no Web APIs, no `fetch`, etc.), which it is.
    let result = try ydl.download.throwing.dynamicallyCall(withArguments: all_urls)
    if let exitCode = Int(result), exitCode != 0 {
        throw NSError(
            domain: "com.leshko.freetube.ytdlp",
            code: exitCode,
            userInfo: [NSLocalizedDescriptionKey: "yt-dlp failed with exit code \(exitCode)."]
        )
    }
}
