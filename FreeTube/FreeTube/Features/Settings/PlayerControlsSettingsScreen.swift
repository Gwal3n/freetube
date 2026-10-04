import SwiftUI

/// System drag-and-drop editor for optional player controls. A ScrollView keeps one drag session
/// across the three sections, while each row and section heading offers a native drop target.
@available(iOS 17.0, *)
struct PlayerControlsSettingsScreen: View {
    @Bindable var model: SettingsViewModel
    @State private var targetedControl: PlayerTopControl?
    @State private var targetedSection: PlayerControlLayout.Section?

    private let dragPrefix = "com.leshko.freetube.player-control:"
    private let rowHeight: CGFloat = 44

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(PlayerControlLayout.Section.allCases) { section in
                    controlSection(section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle("Customize controls")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func controlSection(_ section: PlayerControlLayout.Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: section.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(targetedSection == section ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, _ in
                    accept(items, in: section, before: model.playerControlLayout.controls(in: section).first)
                } isTargeted: { targeted in
                    targetedSection = targeted ? section : nil
                }

            ForEach(model.playerControlLayout.controls(in: section)) { control in
                controlRow(control, in: section)
            }
        }
    }

    private func controlRow(_ control: PlayerTopControl, in section: PlayerControlLayout.Section) -> some View {
        HStack(spacing: 12) {
            Image(systemName: control.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(verbatim: control.displayName)
                .font(.subheadline)
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: rowHeight)
        .contentShape(Rectangle())
        .background(targetedControl == control ? Color.primary.opacity(0.08) : Color.clear)
        .draggable(dragPrefix + control.rawValue)
        .dropDestination(for: String.self) { items, location in
            let controls = model.playerControlLayout.controls(in: section)
            let next = controls.firstIndex(of: control).flatMap { index in
                controls.indices.contains(index + 1) ? controls[index + 1] : nil
            }
            let insertionTarget = location.y < rowHeight / 2 ? control : next
            return accept(items, in: section, before: insertionTarget)
        } isTargeted: { targeted in
            targetedControl = targeted ? control : nil
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
        withAnimation(InterfaceMotion.quick) {
            model.movePlayerControl(control, to: section, before: target)
        }
        targetedControl = nil
        targetedSection = nil
        return true
    }
}
