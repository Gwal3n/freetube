import SwiftUI

/// How the temporary hold-for-speed rate appears on the video.
enum HoldSpeedIndicatorStyle: String, CaseIterable, Identifiable {
    case pill, text, none

    static let storageKey = "holdSpeedIndicatorStyle"
    static let autoHideKey = "holdSpeedIndicatorAutoHide"
    static let hideDelayKey = "holdSpeedIndicatorHideDelay"
    static let defaultHideDelay = 1.0
    static let hideDelayRange = 0.5...10.0

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pill: "Pill"
        case .text: "Text only"
        case .none: "None"
        }
    }

    /// The earlier on/off pill toggle maps to Pill or None.
    static var storedDefault: String {
        UserDefaults.standard.object(forKey: "showHoldSpeedPill") as? Bool == false
            ? none.rawValue
            : pill.rawValue
    }
}
