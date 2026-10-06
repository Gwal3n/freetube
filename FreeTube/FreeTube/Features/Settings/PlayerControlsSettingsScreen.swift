import SwiftUI

/// Native List editing handles order; a row menu handles placement. Keeping those decisions
/// separate avoids custom drop targets and makes moving a control to an empty section possible.
@available(iOS 17.0, *)
struct PlayerControlsSettingsScreen: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        List {
            ForEach(PlayerControlLayout.Section.allCases) { section in
                controlSection(section)
            }
            if model.playerControlLayout.moreMenu.count > 1 {
                menuDividerSection
            }
        }
        .listStyle(.insetGrouped)
        .tint(Color.primary)
        .navigationTitle("Customize controls")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    private func controlSection(_ section: PlayerControlLayout.Section) -> some View {
        let controls = model.playerControlLayout.controls(in: section)

        return Section {
            if controls.isEmpty {
                Text("No controls")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controls) { control in
                    placementMenu(for: control, in: section)
                }
                .onMove { offsets, destination in
                    model.reorderPlayerControls(
                        in: section,
                        fromOffsets: offsets,
                        toOffset: destination
                    )
                }
            }
        } header: {
            Text(verbatim: section.title)
        } footer: {
            if section == .onPlayer {
                Text("Up to four controls can appear on the player. Moving a fifth here moves the last control to More menu.")
            }
        }
    }

    private func placementMenu(
        for control: PlayerTopControl,
        in currentSection: PlayerControlLayout.Section
    ) -> some View {
        Menu {
            ForEach(PlayerControlLayout.Section.allCases) { destination in
                Button {
                    model.movePlayerControl(control, to: destination)
                } label: {
                    Text(verbatim: destination.title)
                    if destination == currentSection {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: control.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                Text(verbatim: control.displayName)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(verbatim: control.displayName))
        .accessibilityHint("Choose whether this control appears on the player, in More menu, or is hidden")
    }

    private var menuDividerSection: some View {
        Section("More menu separators") {
            ForEach(Array(model.playerControlLayout.moreMenu.dropFirst())) { control in
                Toggle(isOn: dividerBinding(before: control)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: control.displayName)
                        Text("Divider above")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func dividerBinding(before control: PlayerTopControl) -> Binding<Bool> {
        Binding(
            get: { model.playerMoreMenuDividers.contains(control) },
            set: { isEnabled in
                var anchors = model.playerMoreMenuDividers
                if isEnabled {
                    anchors.insert(control)
                } else {
                    anchors.remove(control)
                }
                model.playerMoreMenuDividers = anchors
            }
        )
    }
}
