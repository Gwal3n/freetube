import Foundation
import YouTubeKit

/// Keeps the player response's duration while letting the pinned YouTubeKit decoder continue to
/// own the rest of the response. Its `VideoInfosResponse` model does not expose `lengthSeconds`.
nonisolated struct VideoInfosWithRawDurationResponse: YouTubeResponse {
    static let headersType = VideoInfosResponse.headersType
    static let parametersValidationList = VideoInfosResponse.parametersValidationList

    let info: VideoInfosResponse
    let duration: TimeInterval?

    static func decodeData(data: Data) throws -> Self {
        Self(
            info: try VideoInfosResponse.decodeData(data: data),
            duration: duration(from: data)
        )
    }

    static func decodeJSON(json: JSON) throws -> Self {
        let raw = json["videoDetails", "lengthSeconds"].string
        let seconds = raw.flatMap { Double($0) } ?? json["videoDetails", "lengthSeconds"].double
        let duration = seconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return Self(info: try VideoInfosResponse.decodeJSON(json: json), duration: duration)
    }

    static func duration(from data: Data) -> TimeInterval? {
        let html = String(decoding: data, as: UTF8.self)
        guard let marker = html.range(of: "var ytInitialPlayerResponse = "),
              let end = html.range(
                of: ";</script><div id=\"player\"",
                range: marker.upperBound..<html.endIndex
              ),
              let payload = String(html[marker.upperBound..<end.lowerBound]).data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let details = root["videoDetails"] as? [String: Any] else { return nil }

        let seconds: TimeInterval?
        if let text = details["lengthSeconds"] as? String {
            seconds = Double(text)
        } else if let number = details["lengthSeconds"] as? NSNumber {
            seconds = number.doubleValue
        } else {
            seconds = nil
        }
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return seconds
    }
}
