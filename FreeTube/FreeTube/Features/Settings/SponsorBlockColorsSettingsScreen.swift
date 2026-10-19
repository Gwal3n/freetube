import SwiftUI

/// Native per-category color controls for SponsorBlock elements visible in the player.
@available(iOS 17.0, *)
struct SponsorBlockColorsSettingsScreen: View {
    let model: SettingsViewModel
    @AppStorage("sponsorBlockColorOverridesJSON") private var overridesJSON = "{}"

    private var palette: SponsorBlockColorPalette {
        SponsorBlockColorPalette(json: overridesJSON)
    }

    private var visibleCategories: [SponsorBlockCategory] {
        SponsorBlockCategory.allCases.filter {
            $0 != .chapter && model.sponsorBlockBehavior(for: $0) != .disabled
        }
    }

    var body: some View {
        Form {
            if visibleCategories.isEmpty {
                ContentUnavailableView(
                    "No colored categories enabled",
                    systemImage: "paintpalette",
                    description: Text("Enable a SponsorBlock category to customize its color.")
                )
            } else {
                ForEach(visibleCategories) { category in
                    Section {
                        Picker(selection: usesCustomColor(for: category)) {
                            Text("Default").tag(false)
                            Text("Custom").tag(true)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(palette.color(for: category))
                                    .frame(width: 12, height: 12)
                                Text(category.displayName)
                            }
                        }
                        if palette.usesCustomColor(for: category) {
                            ColorPicker("Custom color", selection: customColor(for: category), supportsOpacity: false)
                        }
                    }
                }
            }
        }
        .navigationTitle("Segment colors")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func usesCustomColor(for category: SponsorBlockCategory) -> Binding<Bool> {
        Binding(
            get: { palette.usesCustomColor(for: category) },
            set: { enabled in
                var updated = palette
                updated.setCustomColorEnabled(enabled, for: category)
                overridesJSON = updated.json
            }
        )
    }

    private func customColor(for category: SponsorBlockCategory) -> Binding<Color> {
        Binding(
            get: { palette.color(for: category) },
            set: { color in
                var updated = palette
                updated.setColor(color, for: category)
                overridesJSON = updated.json
            }
        )
    }
}
