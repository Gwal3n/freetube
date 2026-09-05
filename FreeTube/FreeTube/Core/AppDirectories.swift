import Foundation

/// Stable application-container paths that do not depend on Foundation's search-path cache.
/// Embedded Python can alter process path state before a lazy `.documentDirectory` lookup; on
/// device that produced `Documents/Data/Application/<old UUID>/Documents`. `NSHomeDirectory()`
/// remains anchored to the current sandbox container.
nonisolated enum AppDirectories {
    static let documents = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Documents", isDirectory: true)
}
