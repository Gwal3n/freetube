import Foundation

/// Raw seek-preview specification returned with an InnerTube player response.
public struct YouTubeStoryboard: Sendable, Hashable {
    /// Sprite-sheet URL template and level descriptions encoded by YouTube.
    public let specification: String

    /// Index of YouTube's preferred preview level, when supplied.
    public let recommendedLevel: Int?
}
