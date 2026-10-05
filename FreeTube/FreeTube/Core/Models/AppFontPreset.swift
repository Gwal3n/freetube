import Foundation

/// Device-local typography choice for app-authored content. System chrome remains native.
enum AppFontPreset: String, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case helveticaNeue
    case avenirNext

    var id: String { rawValue }
}
