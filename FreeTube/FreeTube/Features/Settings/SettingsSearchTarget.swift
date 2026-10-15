import SwiftUI

/// The setting selected in search, passed only to the pushed destination.
@available(iOS 17.0, *)
struct SettingsSearchTarget: EnvironmentKey {
    static let defaultValue: String? = nil
}

@available(iOS 17.0, *)
extension EnvironmentValues {
    var settingsSearchTarget: String? {
        get { self[SettingsSearchTarget.self] }
        set { self[SettingsSearchTarget.self] = newValue }
    }
}
