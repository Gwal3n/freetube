import Foundation

/// Dependency-neutral access to YouTube's seek-preview sprite sheets.
struct VideoStoryboard: @unchecked Sendable {
    struct Tile: Sendable {
        let url: URL
        let column: Int
        let row: Int
        let columns: Int
        let rows: Int
        let width: Int
        let height: Int
    }

    private let tileResolver: (
        _ time: TimeInterval,
        _ duration: TimeInterval,
        _ maximumWidth: Int,
        _ maximumHeight: Int
    ) -> Tile?

    init(
        tileResolver: @escaping (
            _ time: TimeInterval,
            _ duration: TimeInterval,
            _ maximumWidth: Int,
            _ maximumHeight: Int
        ) -> Tile?
    ) {
        self.tileResolver = tileResolver
    }

    func tile(
        at time: TimeInterval,
        duration: TimeInterval,
        maximumWidth: Int,
        maximumHeight: Int
    ) -> Tile? {
        tileResolver(time, duration, maximumWidth, maximumHeight)
    }
}
