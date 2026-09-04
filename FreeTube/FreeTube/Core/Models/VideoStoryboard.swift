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

    private struct Level {
        let index: Int
        let width: Int
        let height: Int
        let frameCount: Int
        let columns: Int
        let rows: Int
        let intervalMilliseconds: Int
        let nameTemplate: String
        let signature: String
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

    /// Decodes YouTube's `playerStoryboardSpecRenderer` without retaining an extractor-specific
    /// response object. The resulting value can therefore be supplied by either playback backend.
    init?(specification: String, recommendedLevel: Int?) {
        let parts = specification.split(separator: "|", omittingEmptySubsequences: false)
        guard let rawTemplate = parts.first, !rawTemplate.isEmpty else { return nil }
        let levels = parts.dropFirst().enumerated().compactMap { index, rawLevel -> Level? in
            let fields = rawLevel.split(separator: "#", maxSplits: 7, omittingEmptySubsequences: false)
            guard fields.count == 8,
                  let width = Int(fields[0]), width > 0,
                  let height = Int(fields[1]), height > 0,
                  let frameCount = Int(fields[2]), frameCount > 0,
                  let columns = Int(fields[3]), columns > 0,
                  let rows = Int(fields[4]), rows > 0,
                  let intervalMilliseconds = Int(fields[5]), intervalMilliseconds >= 0
            else { return nil }
            return Level(
                index: index,
                width: width,
                height: height,
                frameCount: frameCount,
                columns: columns,
                rows: rows,
                intervalMilliseconds: intervalMilliseconds,
                nameTemplate: String(fields[6]),
                signature: String(fields[7])
            )
        }
        guard !levels.isEmpty else { return nil }
        let template = String(rawTemplate)

        tileResolver = { time, duration, maximumWidth, maximumHeight in
            let fitting = levels.filter { $0.width <= maximumWidth && $0.height <= maximumHeight }
            let candidates = fitting.isEmpty ? levels : fitting
            let preferred = recommendedLevel.flatMap { preferredIndex in
                candidates.first { $0.index == preferredIndex }
            }
            guard let level = preferred ?? candidates.max(by: {
                $0.width * $0.height < $1.width * $1.height
            }) else { return nil }

            let interval = level.intervalMilliseconds > 0
                ? TimeInterval(level.intervalMilliseconds) / 1_000
                : max(duration / TimeInterval(level.frameCount), 0.001)
            let calculatedFrame = Int(floor(max(0, time) / interval))
            let frame = min(max(calculatedFrame, 0), level.frameCount - 1)
            let tilesPerSheet = level.columns * level.rows
            let sheet = frame / tilesPerSheet
            let tile = frame % tilesPerSheet
            let name = level.nameTemplate.replacingOccurrences(of: "$M", with: String(sheet))
            var urlString = template
                .replacingOccurrences(of: "$L", with: String(level.index))
                .replacingOccurrences(of: "$N", with: name)
            urlString += urlString.contains("?") ? "&" : "?"
            urlString += "sigh=\(level.signature)"
            guard let url = URL(string: urlString) else { return nil }
            return Tile(
                url: url,
                column: tile % level.columns,
                row: tile / level.columns,
                columns: level.columns,
                rows: level.rows,
                width: level.width,
                height: level.height
            )
        }
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
