import Foundation
import OSLog

/// Materializes a direct signed media URL. Keeps HTTP behavior and byte-count checks shared by
/// native and YouTubeKit fallback downloads; the caller owns UI progress and final media checks.
@available(iOS 17.0, *)
@MainActor
final class DownloadStreamTransfer {
    private let log = AppLog(subsystem: "com.leshko.freetube", category: "DownloadManager")

    /// Uses a file-backed URLSession task, with bounded parallel ranges for native audio when
    /// supported. The previous AsyncBytes loop suspended per byte and made audio very slow.
    func download(
        from url: URL,
        to destination: URL,
        sendTVClientUserAgent: Bool,
        sourceLabel: String,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: destination)
        var request = URLRequest(url: url)
        if sendTVClientUserAgent {
            // Use the same agent that minted the TVHTML5 URL. Some CDN requests reject a mismatch.
            request.setValue("Mozilla/5.0 (PlayStation; PlayStation 4/12.55) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        }

        // Googlevideo may omit Content-Length while retaining clen. Use it for progress only;
        // never persist or log the signed URL itself.
        let declaredLength = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "clen" })?.value.flatMap(Int64.init)
        let startedAt = Date()

        var usedRanges = false
        if sourceLabel == "native-audio", let declaredLength, declaredLength > 64 * 1024 {
            do {
                usedRanges = try await RangedMediaDownloadService.download(
                    request: request, to: destination, totalBytes: declaredLength,
                    onProgress: onProgress
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                log.notice("[native-audio] range transfer failed; retrying as one request: \(String(describing: error), privacy: .public)")
                try? FileManager.default.removeItem(at: destination)
            }
        }

        let http: HTTPURLResponse?
        if usedRanges {
            http = nil
        } else {
            http = try await DirectFileDownloadService.download(
                request: request,
                to: destination,
                expectedSizeHint: declaredLength,
                onProgress: onProgress
            )
        }
        if let http, !(200..<300).contains(http.statusCode) {
            log.error("[\(sourceLabel, privacy: .public)] HTTP \(http.statusCode, privacy: .public) from \(url.host ?? "?", privacy: .public)\(url.path, privacy: .public)")
            throw YouTubeServiceError.streamExtractionFailed
        }
        let expected = usedRanges ? (declaredLength ?? -1) : (http?.expectedContentLength ?? -1)
        let written = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        log.info("[\(sourceLabel, privacy: .public)] wrote \(written, privacy: .public) bytes in \(Date().timeIntervalSince(startedAt), privacy: .public)s mode=\(usedRanges ? "ranges" : "single", privacy: .public) to \(destination.lastPathComponent, privacy: .public)")

        guard written >= DownloadMediaFinalizer.minimumFileSize else {
            log.error("[\(sourceLabel, privacy: .public)] refusing undersized stream: wrote=\(written, privacy: .public) bytes")
            try? FileManager.default.removeItem(at: destination)
            throw YouTubeServiceError.streamExtractionFailed
        }
        if expected > 0, written != expected {
            log.error("[\(sourceLabel, privacy: .public)] incomplete stream: wrote=\(written, privacy: .public) expected=\(expected, privacy: .public)")
            try? FileManager.default.removeItem(at: destination)
            throw YouTubeServiceError.streamExtractionFailed
        }
    }
}
