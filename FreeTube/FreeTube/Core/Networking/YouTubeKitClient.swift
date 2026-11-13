import Foundation
import OSLog
import YouTubeKit

/// Anonymous `YouTubeModel` handle. Keep `YouTubeKit` imports inside `Core/Networking/`.
nonisolated final class YouTubeKitClient: @unchecked Sendable {
    static let shared = YouTubeKitClient()

    /// iOS client (HLS when available; adaptive URLs may be PoT-protected).
    let model = YouTubeModel()

    /// TVHTML5 embed client for PoT-resistant `/videoplayback` URLs.
    let tvHtmlModel = YouTubeModel()

    private let log = AppLog(subsystem: "com.leshko.freetube", category: "YouTubeKitClient")

    private init() {
        model.cookies = ""
        model.alwaysUseCookies = false
        tvHtmlModel.cookies = ""
        tvHtmlModel.alwaysUseCookies = false
        model.selectedLocale = Self.requestLocale
        tvHtmlModel.selectedLocale = Self.requestLocale
        installTVHTML5Overrides()
    }

    /// Pin titles to English/US rather than device locale or VPN region.
    private static let requestLocale = "en-US"

    private func installTVHTML5Overrides() {
        let bodyPrefix = #"{"context":{"client":{"clientName":"TVHTML5_SIMPLY_EMBEDDED_PLAYER","clientVersion":"2.0","clientScreen":"EMBED","platform":"TV","hl":"en","gl":"US","clientFormFactor":"UNKNOWN_FORM_FACTOR"},"thirdParty":{"embedUrl":"https://www.youtube.com/"}},"contentCheckOk":true,"racyCheckOk":true,"videoId":""#
        let headers = HeadersList(
            url: URL(string: "https://www.youtube.com/youtubei/v1/player")!,
            method: .POST,
            headers: [
                HeadersList.Header(name: "Accept", content: "*/*"),
                HeadersList.Header(name: "Accept-Encoding", content: "gzip, deflate, br"),
                HeadersList.Header(name: "Host", content: "www.youtube.com"),
                HeadersList.Header(name: "User-Agent", content: "Mozilla/5.0 (PlayStation; PlayStation 4/12.55) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Safari/605.1.15"),
                HeadersList.Header(name: "Content-Type", content: "application/json"),
                HeadersList.Header(name: "Origin", content: "https://www.youtube.com"),
                HeadersList.Header(name: "Referer", content: "https://www.youtube.com/")
            ],
            customHeaders: [
                "X-Goog-Visitor-Id": .visitorData
            ],
            addQueryAfterParts: [
                HeadersList.AddQueryInfo(index: 0, encode: false, content: .query)
            ],
            httpBody: [bodyPrefix, "\"}"],
            parameters: [
                HeadersList.ParameterToAdd(name: "prettyPrint", content: "false")
            ]
        )
        tvHtmlModel.customHeaders[.videoInfos] = headers
    }

    func clearVisitorData() {
        model.visitorData = ""
        tvHtmlModel.visitorData = ""
    }

    /// Bootstraps `visitorData` once via a SearchResponse (required by VideoInfosResponse).
    func ensureVisitorData() async {
        guard model.visitorData.isEmpty else { return }
        do {
            let response = try await SearchResponse.sendThrowingRequest(
                youtubeModel: model,
                data: [.query: "music"]
            )
            if let visitorData = response.visitorData, !visitorData.isEmpty {
                model.visitorData = visitorData
                tvHtmlModel.visitorData = visitorData
                log.info("Visitor data bootstrapped")
            } else {
                log.error("SearchResponse returned no visitorData")
            }
        } catch {
            log.error("Visitor-data bootstrap failed: \(String(describing: error), privacy: .public)")
        }
    }
}
