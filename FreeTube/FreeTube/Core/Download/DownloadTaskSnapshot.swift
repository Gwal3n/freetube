import Foundation

/// Public-facing snapshot of a download. DownloadManager exposes these through observable state.
struct DownloadTaskSnapshot: Identifiable, Sendable {
    enum State: Sendable, Equatable {
        case queued
        case downloading(progress: Double)
        case paused
        case completed(URL)
        case failed(String)
    }

    let id: String
    let videoID: String
    let title: String
    let state: State
    let createdAt: Date
}
