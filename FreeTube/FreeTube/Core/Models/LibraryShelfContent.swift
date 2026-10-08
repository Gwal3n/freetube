import Foundation

enum LibraryShelfContent: String, CaseIterable, Identifiable {
    case recent
    case continueWatching

    var id: String { rawValue }

    var shelfTitle: String {
        switch self {
        case .recent: String(localized: "Recently watched")
        case .continueWatching: String(localized: "Continue watching")
        }
    }

    var settingsTitle: String {
        switch self {
        case .recent: String(localized: "All watch history")
        case .continueWatching: String(localized: "Continue watching")
        }
    }
}
