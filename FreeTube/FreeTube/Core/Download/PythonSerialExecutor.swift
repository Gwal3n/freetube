import Foundation

/// `SerialExecutor` that dispatches all jobs to a single serial `DispatchQueue`. The queue's
/// worker-thread stability is what makes Python happy — Python's per-thread state was set up
/// on whichever worker handled the first job and stays valid because GCD reuses the same worker
/// for the queue's subsequent jobs.
@available(iOS 17.0, *)
final class PythonSerialExecutor: SerialExecutor, @unchecked Sendable {
    // `.utility` keeps the Python thread off `.userInitiated` priority — downloads are
    // background work, not UI-blocking, so they shouldn't compete with the main thread for
    // CPU. With `.userInitiated`, list scrolling visibly stuttered while yt-dlp was reading
    // SSL data.
    private let queue = DispatchQueue(label: "com.leshko.freetube.python", qos: .utility)

    func enqueue(_ job: UnownedJob) {
        let unowned = asUnownedSerialExecutor()
        queue.async {
            job.runSynchronously(on: unowned)
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}
