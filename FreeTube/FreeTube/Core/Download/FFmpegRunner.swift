import Foundation
import FFmpegSupport

/// Serializes ffmpeg calls. The C library and `+faststart` pass are not thread-safe.
@available(iOS 17.0, *)
actor FFmpegRunner {
    static let shared = FFmpegRunner()

    private var pending: Task<Void, Never>?

    private init() {}

    /// Runs ffmpeg off the main actor; concurrent callers wait their turn.
    func run(_ args: [String]) async -> Int32 {
        let previous = pending

        let task = Task<Int32, Never>.detached(priority: .utility) {
            await previous?.value
            return Int32(ffmpeg(args))
        }

        pending = Task<Void, Never> { _ = await task.value }

        return await task.value
    }
}
