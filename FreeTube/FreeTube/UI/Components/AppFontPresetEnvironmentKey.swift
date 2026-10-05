import SwiftUI

@available(iOS 17.0, *)
private struct AppFontPresetEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppFontPreset = .system
}

@available(iOS 17.0, *)
extension EnvironmentValues {
    var appFontPreset: AppFontPreset {
        get { self[AppFontPresetEnvironmentKey.self] }
        set { self[AppFontPresetEnvironmentKey.self] = newValue }
    }
}
