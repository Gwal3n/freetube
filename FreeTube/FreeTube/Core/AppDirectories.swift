import Foundation

/// Stable application-container paths that do not depend on Foundation's search-path cache.
/// Embedded Python can alter process path state before a lazy `.documentDirectory` lookup; on
/// device that produced `Documents/Data/Application/<old UUID>/Documents`. `NSHomeDirectory()`
/// remains anchored to the current sandbox container.
nonisolated enum AppDirectories {
    static let documents: URL = {
        let reportedHome = NSHomeDirectory()

        // Python-iOS may rewrite HOME to a path nested below the real Documents directory, e.g.
        // `<current container>/Documents/Data/Application/<old container>`. The first Documents
        // component still unambiguously marks the current sandbox root, so trim there.
        if let marker = reportedHome.range(of: "/Documents/") {
            let container = String(reportedHome[..<marker.lowerBound])
            return URL(fileURLWithPath: container, isDirectory: true)
                .appendingPathComponent("Documents", isDirectory: true)
        }
        if reportedHome.hasSuffix("/Documents") {
            return URL(fileURLWithPath: reportedHome, isDirectory: true)
        }
        return URL(fileURLWithPath: reportedHome, isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
    }()
}
