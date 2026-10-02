import Foundation

/// Fetches a known-size progressive audio stream in a few independent byte ranges. Some media
/// servers pace a single long-lived response close to playback speed; bounded parallel ranges
/// avoid making an 18 MB audio file take many minutes. A server that ignores Range returns nil
/// from the probe, allowing the caller to use its existing single-request transfer instead.
@available(iOS 17.0, *)
nonisolated enum RangedAudioDownloadService {
    private static let probeLength: Int64 = 64 * 1024
    private static let chunkLength: Int64 = 1024 * 1024
    private static let maximumConcurrentChunks = 4

    private enum RangeError: Error {
        case invalidResponse
    }

    /// Returns false without creating `destination` when the server does not support ranges.
    static func download(
        request: URLRequest,
        to destination: URL,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> Bool {
        guard totalBytes > probeLength else { return false }
        try Task.checkCancellation()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let probeEnd = min(totalBytes - 1, probeLength - 1)
        guard let firstChunk = try await fetchRange(
            request: request, session: session, start: 0, end: probeEnd, totalBytes: totalBytes
        ) else { return false }

        try? FileManager.default.removeItem(at: destination)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        do {
            try handle.truncate(atOffset: UInt64(totalBytes))
            try handle.write(contentsOf: firstChunk)
            var completedBytes = Int64(firstChunk.count)
            onProgress(completedBytes, totalBytes)

            var ranges: [(start: Int64, end: Int64)] = []
            var start = probeEnd + 1
            while start < totalBytes {
                let end = min(totalBytes - 1, start + chunkLength - 1)
                ranges.append((start, end))
                start = end + 1
            }

            try await withThrowingTaskGroup(of: (Int64, Data).self) { group in
                for range in ranges.prefix(maximumConcurrentChunks) {
                    group.addTask {
                        guard let data = try await fetchRange(
                            request: request, session: session,
                            start: range.start, end: range.end, totalBytes: totalBytes
                        ) else { throw RangeError.invalidResponse }
                        return (range.start, data)
                    }
                }
                var next = min(maximumConcurrentChunks, ranges.count)
                while let (offset, data) = try await group.next() {
                    try Task.checkCancellation()
                    try handle.seek(toOffset: UInt64(offset))
                    try handle.write(contentsOf: data)
                    completedBytes += Int64(data.count)
                    onProgress(completedBytes, totalBytes)
                    if next < ranges.count {
                        let range = ranges[next]
                        next += 1
                        group.addTask {
                            guard let data = try await fetchRange(
                                request: request, session: session,
                                start: range.start, end: range.end, totalBytes: totalBytes
                            ) else { throw RangeError.invalidResponse }
                            return (range.start, data)
                        }
                    }
                }
            }
            guard completedBytes == totalBytes else { throw RangeError.invalidResponse }
            return true
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Validate both the response range and byte count. A 200 response means Range was ignored;
    /// accepting its data for any chunk would silently corrupt the assembled file.
    private static func fetchRange(
        request: URLRequest,
        session: URLSession,
        start: Int64,
        end: Int64,
        totalBytes: Int64
    ) async throws -> Data? {
        var ranged = request
        ranged.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        ranged.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (data, response) = try await session.data(for: ranged)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 206,
              http.value(forHTTPHeaderField: "Content-Range") == "bytes \(start)-\(end)/\(totalBytes)",
              data.count == Int(end - start + 1) else { return nil }
        return data
    }
}
