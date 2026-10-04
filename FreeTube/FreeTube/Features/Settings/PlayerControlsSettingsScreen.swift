import SwiftUI

/// Native drag-and-drop editor for the optional controls in the video's top-right corner.
/// The collapse button and central transport controls are fixed and cannot be hidden.
@available(iOS 17.0, *)
struct PlayerControlsSettingsScreen: View {
    @Bindable var model: SettingsViewModel
    @State private var targetedControl: PlayerTopControl?
    @State private var targetedSection: PlayerControlLayout.Section?

    private let dragPrefix = "com.leshko.freetube.player-control:"

    var body: some View {
        List {
            ForEach(PlayerControlLayout.Section.allCases) { section in
                Section {
                    ForEach(model.playerControlLayout.controls(in: section)) { control in
                        controlRow(control, in: section)
                    }
                    dropAtEnd(in: section)
                } header: {
                    Text(verbatim: section.title)
                } footer: {
                    if section == .onPlayer {
                        Text("Up to four controls appear beside the fixed player buttons. Adding another moves the last control into More.")
                    } else if section == .moreMenu {
                        Text("The More button appears only when this section contains controls.")
                    } else {
                        Text("Hidden controls can be dragged back at any time.")
                    }
                }
            }
        }
        .navigationTitle("Customize controls")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func controlRow(_ control: PlayerTopControl, in section: PlayerControlLayout.Section) -> some View {
        HStack(spacing: 12) {
            Image(systemName: control.systemImage)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(verbatim: control.displayName)
            Spacer(minLength: 8)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .background {
            if targetedControl == control {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.16))
            }
        }
        .draggable(dragPrefix + control.rawValue)
        .dropDestination(for: String.self) { items, _ in
            accept(items, in: section, before: control)
        } isTargeted: { isTargeted in
            if isTargeted {
                targetedControl = control
            } else if targetedControl == control {
                targetedControl = nil
            }
        }
        .accessibilityHint("Drag to reorder or move to another section")
        .accessibilityAction(named: "Move to player") {
            model.movePlayerControl(control, to: .onPlayer)
        }
        .accessibilityAction(named: "Move to More menu") {
            model.movePlayerControl(control, to: .moreMenu)
        }
        .accessibilityAction(named: "Hide control") {
            model.movePlayerControl(control, to: .hidden)
        }
    }

    private func dropAtEnd(in section: PlayerControlLayout.Section) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.dashed")
            Text("Drop here to add at end")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .background {
            if targetedSection == section {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.16))
            }
        }
        .dropDestination(for: String.self) { items, _ in
            accept(items, in: section, before: nil)
        } isTargeted: { isTargeted in
            if isTargeted {
                targetedSection = section
            } else if targetedSection == section {
                targetedSection = nil
            }
        }
    }

    private func accept(
        _ items: [String],
        in section: PlayerControlLayout.Section,
        before target: PlayerTopControl?
    ) -> Bool {
        guard let payload = items.first,
              payload.hasPrefix(dragPrefix),
              let control = PlayerTopControl(rawValue: String(payload.dropFirst(dragPrefix.count))) else {
            return false
        }
        withAnimation(.snappy(duration: 0.22)) {
            model.movePlayerControl(control, to: section, before: target)
        }
        return true
    }
}
