import SwiftUI

@available(iOS 17.0, *)
struct AppearanceSettingsScreen: View {
    @Environment(\.settingsToggleTint) private var settingsToggleTint
    let model: SettingsViewModel
    @AppStorage("appearanceMode") private var appearanceModeRaw = AppearanceMode.dark.rawValue
    @AppStorage("appAccentPreset") private var appAccentPresetRaw = AppAccentPreset.classic.rawValue
    @AppStorage("useAccentTheme") private var useAccentTheme = false
    @AppStorage("accentNavigationOnly") private var accentNavigationOnly = false
    @AppStorage("appCustomAccentHex") private var appCustomAccentHex = "#FF3B30"

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appearanceModeRaw) {
                    Text("System").tag(AppearanceMode.system.rawValue)
                    Text("Light").tag(AppearanceMode.light.rawValue)
                    Text("Dark").tag(AppearanceMode.dark.rawValue)
                }
                .settingsSearchRow("Appearance")
                Toggle("Use accent colors", isOn: $useAccentTheme)
                    .tint(settingsToggleTint)
                    .settingsSearchRow("Use accent colors")
                if useAccentTheme {
                    Toggle("Accent navigation bar only", isOn: $accentNavigationOnly)
                        .tint(settingsToggleTint)
                        .settingsSearchRow("Accent navigation bar only")
                    Picker("Accent color", selection: $appAccentPresetRaw) {
                        ForEach(AppAccentPreset.allCases) { preset in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(preset.color(customHex: appCustomAccentHex))
                                    .frame(width: 18, height: 18)
                                Text(preset.label)
                                    .foregroundStyle(.primary)
                            }
                            .tag(preset.rawValue)
                        }
                    }
                    .settingsSearchRow("Accent color")
                    if appAccentPresetRaw == AppAccentPreset.custom.rawValue {
                        ColorPicker("Custom accent color", selection: Binding(
                            get: { WatchIndicatorStyle.color(hex: appCustomAccentHex) ?? .red },
                            set: { appCustomAccentHex = WatchIndicatorStyle.hex(color: $0) }
                        ), supportsOpacity: false)
                        .settingsSearchRow("Custom accent color")
                    }
                }
                Picker("Text font", selection: Bindable(model).appFontPreset) {
                    ForEach(AppFontPreset.allCases) { preset in
                        preset.label
                            .font(preset.font(.body))
                            .tag(preset)
                    }
                }
                .settingsSearchRow("Text font")
            } footer: {
                Text("The player interface follows your appearance; the video canvas stays black.")
            }

            Section("Navigation") {
                NavigationLink {
                    TabBarSettingsScreen()
                } label: {
                    Label("Tab Bar", systemImage: "square.grid.2x2")
                }
                .settingsSearchRow("Tab Bar")
            }
        }
        .scrollToSearchedSetting()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}
