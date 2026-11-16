import SwiftUI

/// Resolves the saved scrubber color for every player progress surface, so the timeline, live
/// timeline, and mini-player bar always agree.
struct PlayerScrubberTint: DynamicProperty {
    @AppStorage("playerScrubberColorMode") private var modeRaw = PlayerScrubberColorMode.standard.rawValue
    @AppStorage("playerScrubberCustomHex") private var customHex = "#FF0000"
    @AppStorage("appAccentPreset") private var accentPresetRaw = AppAccentPreset.classic.rawValue
    @AppStorage("appCustomAccentHex") private var accentHex = "#FF3B30"

    init() {}

    var color: Color {
        (PlayerScrubberColorMode(rawValue: modeRaw) ?? .standard).color(
            customHex: customHex,
            accent: AppAccentPreset(rawValue: accentPresetRaw) ?? .classic,
            accentHex: accentHex
        )
    }
}
