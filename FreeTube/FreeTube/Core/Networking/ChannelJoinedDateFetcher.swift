import Foundation

/// Anonymous about-tab lookup for the channel preview's join-date footer.
@available(iOS 17.0, *)
enum ChannelJoinedDateFetcher {
    /// Stable about-tab `params` used by yt-dlp / Invidious for channel About.
    private static let aboutParams = "EgVhYm91dPIGBAoCEgA%3D"

    static func fetch(channelID: String) async -> String? {
        let id = channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        let url = URL(string: "https://www.youtube.com/youtubei/v1/browse?prettyPrint=false")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.httpBody = browseBody(channelID: id)

        do {
            let (data, response) = try await AnonymousURLSession.make().data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return extractJoinedText(from: root)
        } catch {
            return nil
        }
    }

    private static func browseBody(channelID: String) -> Data {
        let payload: [String: Any] = [
            "context": [
                "client": [
                    "hl": "en",
                    "gl": "US",
                    "clientName": "WEB",
                    "clientVersion": "2.20260213.01.00",
                    "deviceMake": "Apple",
                    "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Safari/605.1.15,gzip(gfe)",
                    "osName": "Macintosh",
                    "osVersion": "10_15_7",
                    "platform": "DESKTOP",
                    "clientFormFactor": "UNKNOWN_FORM_FACTOR",
                    "browserName": "Safari",
                    "browserVersion": "16.2"
                ],
                "user": ["lockedSafetyMode": false],
                "request": ["useSsl": true]
            ],
            "browseId": channelID,
            "params": aboutParams
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    /// Walks the about response for `joinedDateText.content` (e.g. "Joined Dec 12, 2014").
    private static func extractJoinedText(from root: Any) -> String? {
        if let dict = root as? [String: Any] {
            if let joined = dict["joinedDateText"] as? [String: Any],
               let content = joined["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let content = dict["content"] as? String,
               content.localizedCaseInsensitiveContains("joined") {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            for value in dict.values {
                if let found = extractJoinedText(from: value) { return found }
            }
        } else if let array = root as? [Any] {
            for value in array {
                if let found = extractJoinedText(from: value) { return found }
            }
        }
        return nil
    }
}
