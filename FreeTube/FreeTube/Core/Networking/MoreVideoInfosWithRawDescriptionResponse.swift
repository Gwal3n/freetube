import Foundation
import YouTubeKit

/// Decodes the description alongside b5i's metadata from the same response bytes. Its parser
/// indexes command runs by Swift Characters, but YouTube supplies UTF-16 offsets; links after
/// emoji can otherwise be attached to the wrong text. Parsing here keeps JSON work off the UI.
nonisolated struct MoreVideoInfosWithRawDescriptionResponse: YouTubeResponse {
    static let headersType = MoreVideoInfosResponse.headersType
    static let parametersValidationList = MoreVideoInfosResponse.parametersValidationList

    let info: MoreVideoInfosResponse
    let description: (text: String, parts: [VideoDescriptionPart])?

    static func decodeData(data: Data) throws -> Self {
        Self(
            info: try MoreVideoInfosResponse.decodeData(data: data),
            description: VideoDescriptionExtractor.extract(from: data)
        )
    }

    static func decodeJSON(json: JSON) throws -> Self {
        Self(info: MoreVideoInfosResponse.decodeJSON(json: json), description: nil)
    }
}
