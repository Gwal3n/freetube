import Foundation

/// Sheet identity for custom upload/length/views ranges shared by Search, Feed, and local playlists.
@available(iOS 17.0, *)
enum MediaFilterCustomRange: String, Identifiable, CaseIterable {
    case uploaded, length, views

    var id: String { rawValue }
}
