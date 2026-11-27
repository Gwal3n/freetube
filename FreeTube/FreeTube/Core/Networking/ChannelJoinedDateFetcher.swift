import Foundation

/// Anonymous lookup for the channel preview's join-date label.
///
/// YouTube retired the `/about` browse `params` path. Join date now lives on the channel
/// engagement-panel continuation (`aboutChannelViewModel.joinedDateText`).
@available(iOS 17.0, *)
enum ChannelJoinedDateFetcher {
    private static let browseURL = URL(string: "https://www.youtube.com/youtubei/v1/browse?prettyPrint=false")!

    static func fetch(channelID: String) async -> String? {
        let id = channelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        do {
            let channelPage = try await post(browseBody(browseID: id))
            if let direct = extractJoinedText(from: channelPage) {
                return direct
            }
            for token in engagementContinuationTokens(from: channelPage) {
                let panel = try await post(continuationBody(token: token))
                if let joined = extractJoinedText(from: panel) {
                    return joined
                }
            }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Networking

    private static func post(_ body: Data) async throws -> Any {
        var request = URLRequest(url: browseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.2 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.httpBody = body

        let (data, response) = try await AnonymousURLSession.make().data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func browseBody(browseID: String) -> Data {
        let payload: [String: Any] = [
            "context": ["client": clientContext()],
            "browseId": browseID
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private static func continuationBody(token: String) -> Data {
        let payload: [String: Any] = [
            "context": ["client": clientContext()],
            "continuation": token
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    private static func clientContext() -> [String: Any] {
        [
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
        ]
    }

    // MARK: - Extraction

    /// Unique continuation tokens from `showEngagementPanelEndpoint` nodes on the channel page.
    private static func engagementContinuationTokens(from root: Any) -> [String] {
        var tokens: [String] = []
        var seen = Set<String>()
        walk(root) { dict in
            guard dict["showEngagementPanelEndpoint"] != nil else { return }
            guard let token = firstContinuationToken(in: dict), !token.isEmpty, seen.insert(token).inserted else {
                return
            }
            tokens.append(token)
        }
        return tokens
    }

    private static func firstContinuationToken(in root: Any) -> String? {
        if let dict = root as? [String: Any] {
            if let command = dict["continuationCommand"] as? [String: Any],
               let token = command["token"] as? String,
               !token.isEmpty {
                return token
            }
            for value in dict.values {
                if let token = firstContinuationToken(in: value) { return token }
            }
        } else if let array = root as? [Any] {
            for value in array {
                if let token = firstContinuationToken(in: value) { return token }
            }
        }
        return nil
    }

    /// Prefers `joinedDateText.content` (e.g. "Joined Mar 21, 2008").
    private static func extractJoinedText(from root: Any) -> String? {
        if let dict = root as? [String: Any] {
            if let joined = dict["joinedDateText"] as? [String: Any] {
                if let content = joined["content"] as? String {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
                if let simple = joined["simpleText"] as? String {
                    let trimmed = simple.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            if let content = dict["content"] as? String,
               content.range(of: #"^Joined\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
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

    private static func walk(_ root: Any, visit: ([String: Any]) -> Void) {
        if let dict = root as? [String: Any] {
            visit(dict)
            for value in dict.values {
                walk(value, visit: visit)
            }
        } else if let array = root as? [Any] {
            for value in array {
                walk(value, visit: visit)
            }
        }
    }
}
