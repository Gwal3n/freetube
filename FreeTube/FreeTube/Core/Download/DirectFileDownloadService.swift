import Foundation

/// File-backed HTTPS transfer shared by native audio-only and direct Link downloads.
/// `URLSessionDownloadTask` writes to disk in native chunks instead of suspending Swift once per
/// byte. Each transfer owns its session/delegate, so cancellation and progress cannot leak between
/// simultaneous downloads. The caller still validates the media before publishing completion.
@available(iOS 17.0, *)
nonisolated final class DirectFileDownloadService: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let expectedSizeHint: Int64?
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<HTTPURLResponse, Error>?
    private var moveError: Error?
    private var lastProgressAt: ContinuousClock.Instant?

    private init(
        destination: URL,
        expectedSizeHint: Int64?,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) {
        self.destination = destination
        self.expectedSizeHint = expectedSizeHint
        self.onProgress = onProgress
        super.init()
    }

    /// Downloads into `destination` and returns the HTTP response. A non-2xx response is returned
    /// without a file so each caller can preserve its own error wording and fallback policy.
    static func download(
        request: URLRequest,
        to destination: URL,
        expectedSizeHint: Int64? = nil,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> HTTPURLResponse {
        try Task.checkCancellation()
        let transfer = DirectFileDownloadService(
            destination: destination,
            expectedSizeHint: expectedSizeHint,
            onProgress: onProgress
        )
        return try await transfer.run(request: request)
    }

    private func run(request: URLRequest) async throws -> HTTPURLResponse {
        // Signed stream URLs must not enter a persistent URL cache or cookie store.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: request)
        do {
            let response = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    // Installed before resume: delegate completion can never beat the waiter.
                    self.continuation = continuation
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            return response
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = ContinuousClock.now
        if let lastProgressAt,
           now - lastProgressAt < .milliseconds(200),
           totalBytesWritten != totalBytesExpectedToWrite { return }
        lastProgressAt = now
        let total = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : (expectedSizeHint ?? 0)
        onProgress(totalBytesWritten, total)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else { return }
        do {
            // The system deletes `location` after this callback returns. Move it now, not after
            // the async waiter resumes; the destination is caller-owned and already cleared.
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else if let moveError {
            continuation.resume(throwing: moveError)
        } else if let response = task.response as? HTTPURLResponse {
            if (200..<300).contains(response.statusCode),
               !FileManager.default.fileExists(atPath: destination.path) {
                continuation.resume(throwing: URLError(.cannotCreateFile))
            } else {
                continuation.resume(returning: response)
            }
        } else {
            continuation.resume(throwing: URLError(.badServerResponse))
        }
    }
}
