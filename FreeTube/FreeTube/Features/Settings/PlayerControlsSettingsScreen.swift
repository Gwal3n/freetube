import SwiftUI

/// Native List editing handles order within each section. A separate row action changes placement,
/// including moves into empty sections, without making the entire row compete with drag handles.
@available(iOS 17.0, *)
struct PlayerControlsSettingsScreen: View {
    @Bindable var model: SettingsViewModel
    @State private var editMode = EditMode.active
    @State private var showsMenuSeparators = false

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
        .environment(\.editMode, $editMode)
        .navigationTitle("Customize controls")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func controlSection(_ section: PlayerControlLayout.Section) -> some View {
        let controls = model.playerControlLayout.controls(in: section)

        return Section {
            if controls.isEmpty {
                Text("No controls")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(controls) { control in
                    controlRow(for: control, in: section)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 8))
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
        }
    }

    private func controlRow(
        for control: PlayerTopControl,
        in currentSection: PlayerControlLayout.Section
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: control.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(verbatim: control.displayName)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)

            placementMenu(for: control, in: currentSection)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Change placement for \(control.displayName)"))
    }

    private var menuDividerSection: some View {
        Section {
            DisclosureGroup("More menu separators", isExpanded: $showsMenuSeparators) {
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
