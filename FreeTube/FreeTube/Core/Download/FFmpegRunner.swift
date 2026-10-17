import Foundation
import FFmpegSupport

/// Serializes every call into the ffmpeg C library.
///
/// **Why this is necessary:** `FFmpegSupport.ffmpeg(_:)` is a re-entrant entry point into a C
/// library with shared global state — most painfully the `+faststart` post-pass (which calls
/// `ff_format_shift_data` to move the moov atom to the front of the file). That pass walks
/// global I/O buffers and is *not* thread-safe; two concurrent invocations on the cooperative
/// thread pool race on `_platform_memmove` and crash with EXC_BAD_ACCESS. The `Hook.m` shim also
/// uses `setjmp`/`longjmp`, which has undefined behavior across concurrent calls.
///
/// Parallel playlist downloads (Download All firing N `ensureDownloaded` tasks at once) was the
/// trigger that exposed this — each yt-dlp completion fed into its own `Task.detached` ffmpeg
/// call. With this actor, every ffmpeg invocation chains strictly behind the previous one
/// through `pending`, same FIFO pattern `PythonRunner` uses for yt-dlp.
@available(iOS 17.0, *)
actor FFmpegRunner {
    static let shared = FFmpegRunner()

    /// Tail of the in-flight FIFO. New callers await this before invoking ffmpeg, so only one
    /// ffmpeg call is ever in flight at a time even though the actor body itself can suspend.
    private var pending: Task<Void, Never>?

    private init() {}

    /// Runs ffmpeg with the given argv off the main actor and returns its exit code. Concurrent
    /// callers are queued — they don't run until the previous ffmpeg call has fully returned.
    func run(_ args: [String]) async -> Int32 {
        let previous = pending

        // Detach onto a `.utility` worker so the ffmpeg C work doesn't block the actor's own
        // executor *and* doesn't compete with main-thread UI priority. We `await previous?.value`
        // first to enforce the serial-FIFO invariant.
        let task = Task<Int32, Never>.detached(priority: .utility) {
            await previous?.value
            return Int32(ffmpeg(args))
        }

        pending = Task<Void, Never> { _ = await task.value }

        return await task.value
    }
}
