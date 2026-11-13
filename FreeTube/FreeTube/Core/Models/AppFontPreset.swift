import Foundation

enum AppFontPreset: String, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case helveticaNeue
    case avenirNext

    var id: String { rawValue }
}
