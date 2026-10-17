import Foundation
import Observation
import OSLog
import PythonKit

/// Runs every Python / yt-dlp call on a single dedicated background thread, off the main actor.
///
/// **The two failure modes this solves:**
/// 1. **Wrong-thread crash.** PythonKit + CPython assume only one thread touches the interpreter
///    — specifically, the same thread that ran `PythonSupport.initialize()`. A plain `actor` runs
///    its methods on its own cooperative-queue executor, where workers rotate between threads —
///    Python's `_PyInterpreterState_GET` crashes the moment it sees an unrecognized worker. We fix
///    this with a **custom `SerialExecutor`** backed by a serial `DispatchQueue`: GCD reuses the
///    same worker thread back-to-back for serial-queue jobs, so Python sees a stable thread.
/// 2. **Reentrancy interleaving.** Actor methods only guarantee one *body* runs at a time — but
///    when that body suspends at an `await`, the executor is free to pick up the next caller. So
///    even a serial actor can have two `yt_dlp` calls suspended on it simultaneously, tramping
///    each other's interpreter state. We fix this with a serial pump over priority queues:
///    each job finishes before the pump starts the next yt-dlp invocation.
@available(iOS 17.0, *)
actor PythonRunner {
    static let shared = PythonRunner()

    /// `nonisolated` so we can log from anywhere — including the detached pump task
    /// without an actor hop. Used by every choke point on the Link-probe / YouTube-download
    /// path so a TestFlight log can pinpoint exactly which step stalled.
    @ObservationIgnored private nonisolated let log = AppLog(subsystem: "com.leshko.freetube", category: "PythonRunner")

    /// Priority levels for incoming yt-dlp work. `.high` is reserved for downloads the user is
    /// actively waiting on (e.g. tapping a video in search results — they want playback now).
    /// `.low` is the default for background work (playlist Download All, queue prefetch).
    /// Within the same priority, items are processed FIFO. A high-priority arrival jumps ahead
    /// of every pending low-priority item but **cannot** preempt the currently-running yt-dlp:
    /// Python's interpreter has no safe interrupt point.
    enum Priority {
        case high
        case low
    }

    /// Pins this actor to a dedicated background-thread executor (NOT the main actor's executor and
    /// NOT the cooperative pool). GCD's serial queue gives us thread stability "in practice" —
    /// back-to-back jobs on the same serial queue use the same worker thread, which is what
    /// PythonKit needs.
    private nonisolated let executor = PythonSerialExecutor()
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

    /// A unit of work runnable on the Python-isolated execution context. Each job handles
    /// its own completion (resuming whatever continuation the public-API call created), so
    /// `pump()` just runs yt-dlp downloads sequentially on the Python executor.
    private typealias Job = @Sendable () async -> Void

    private var highPriority: [Job] = []
    private var lowPriority: [Job] = []
    /// True while a yt-dlp invocation is in flight. The pump loop sets this on entry and clears
    /// on exit; any reentrant `run(…)` calls that arrive during the `await` see this flag, just
    /// enqueue their ticket, and exit without spawning a parallel pump.
    private var isRunning = false

    private init() {}

    /// Submit a yt-dlp run. The call suspends until this ticket reaches the front of its
    /// priority lane AND any in-flight yt-dlp finishes — guaranteeing strict serialization
    /// (Python interpreter can only host one yt-dlp at a time) while letting `.high` callers
    /// jump ahead of any pending `.low` backlog.
    ///
    /// Default priority is `.low`. Pass `.high` from playback paths where the user is actively
    /// waiting for the video to start (search/home tap, play-next, mini-player resume).
    func run(argv: [String],
             progress: @escaping @Sendable ([String: PythonObject]) -> Void,
             log ytLog: @escaping @Sendable (String, String) -> Void,
             priority: Priority = .low) async throws {
        log.info("[PythonRunner.run] enqueue priority=\(String(describing: priority), privacy: .public) argv0=\(argv.first ?? "?", privacy: .public)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let log = self.log
            let job: Job = {
                log.info("[PythonRunner.run] job starting freetube_yt_dlp")
                do {
                    try await freetube_yt_dlp(argv: argv, progress: progress, log: ytLog)
                    log.info("[PythonRunner.run] job completed")
                    continuation.resume()
                } catch {
                    log.error("[PythonRunner.run] job threw: \(String(describing: error), privacy: .public)")
                    continuation.resume(throwing: error)
                }
            }
            switch priority {
            case .high: highPriority.append(job)
            case .low:  lowPriority.append(job)
            }
            log.info("[PythonRunner.run] enqueued; spawning pump (queue high=\(self.highPriority.count, privacy: .public) low=\(self.lowPriority.count, privacy: .public) isRunning=\(self.isRunning, privacy: .public))")
            // Spawn a pump task — if one's already running it's a no-op, otherwise it drains
            // the queues sequentially. Detached to keep the priority on the work, not on the
            // caller (a UI-tap-priority caller shouldn't pin the entire download chain to that
            // priority — see `.utility` choice in the pump loop).
            Task { await self.pump() }
        }
    }

    /// Drains the queues one ticket at a time. Always pulls from `highPriority` first, so a
    /// `.high` arrival during a long `.low` backlog runs immediately after the currently-executing
    /// item — not at the end of the queue.
    ///
    /// **Why `freetube_yt_dlp(...)` instead of the package's `yt_dlp(...)`:** the package's
    /// function doesn't expose a splice point between `injectFakePopen` (which replaces
    /// `subprocess.Popen` with an ffmpeg-only `Pop`) and `ydl.download`. We need to insert
    /// `PythonJSBridge.install()` at exactly that point so yt-dlp's `deno`-based n-cipher
    /// solver transparently routes through our JavaScriptCore shim. See
    /// `Core/JavaScript/FreeTubeYtDlp.swift` for the longer rationale.
    ///
    /// **Why `Task.detached(priority: .utility) { ... }` and NOT plain `Task { ... }`:** this
    /// project has `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` set. Under that setting, an
    /// unstructured `Task { ... }` closure (with no explicit isolation) is treated as
    /// `@MainActor` — even when created from inside a non-main actor like `PythonRunner`. The
    /// inner `try await freetube_yt_dlp(...)` would then execute on the main thread, dragging
    /// every Python eval, SSL handshake, and yt-dlp extractor call onto main and producing
    /// a long "main thread hung" stack (visible as `_ssl__SSLSocket_do_handshake` → … →
    /// `freetube_yt_dlp` → `closure #1 in PythonRunner.pump()` on Thread 1).
    ///
    /// `Task.detached` is the explicit "do NOT inherit isolation" form — it always runs in a
    /// nonisolated context (cooperative thread pool). That's also the historical behavior the
    /// PythonRunner architecture was designed for: CPython runs on a stable cooperative-pool
    /// worker, off the main thread, off the PythonSerialExecutor queue (so GCD priority
    /// escalation from main awaiting `.utility` doesn't apply either).
    ///
    /// **Don't change this back to plain `Task { ... }` without also turning off
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION` for this file.** Plain `Task` only worked before that
    /// build setting was introduced.
    /// `@_optimize(none)` is intentionally kept here even though the project-level
    /// `SWIFT_OPTIMIZATION_LEVEL = "-Onone"` for Release already disables optimization.
    /// It belongs to the diagnostic-clutter set noted in commit 137ead99 ("All 19 critical
    /// PythonKit dlsym symbols present") that should only be reverted **one at a time,**
    /// after each TestFlight build confirms the previous step still works. Reverting all
    /// three (this annotation + the two pbxproj knobs) at once is what caused the
    /// TestFlight hang where yt-dlp update + Link probe spin forever — Swift's whole-module
    /// optimizer breaks the PythonKit/CPython single-thread interpreter discipline.
    @_optimize(none)
    private func pump() async {
        guard !isRunning else {
            log.info("[PythonRunner.pump] already running, exiting")
            return
        }
        isRunning = true
        defer {
            isRunning = false
            log.info("[PythonRunner.pump] queue drained, exiting")
        }
        log.info("[PythonRunner.pump] entering drain loop (high=\(self.highPriority.count, privacy: .public) low=\(self.lowPriority.count, privacy: .public))")

        var ticketNumber = 0
        while let job = takeNext() {
            ticketNumber += 1
            let n = ticketNumber
            log.info("[PythonRunner.pump] ticket #\(n, privacy: .public) starting on detached .utility task")
            // Each job already owns its continuation and handles its own throwing; we just
            // run it on the cooperative pool and wait for completion before pulling the
            // next item. Strict serialization — never two Python interpreters at once.
            let task = Task.detached(priority: .utility) {
                await job()
            }
            _ = await task.value
            log.info("[PythonRunner.pump] ticket #\(n, privacy: .public) finished; next…")
        }
    }

    private func takeNext() -> Job? {
        if !highPriority.isEmpty { return highPriority.removeFirst() }
        if !lowPriority.isEmpty { return lowPriority.removeFirst() }
        return nil
    }
}
