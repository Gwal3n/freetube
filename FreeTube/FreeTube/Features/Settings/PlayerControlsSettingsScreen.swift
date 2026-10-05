import SwiftUI
import UIKit

/// System drag-and-drop editor for optional player controls. A plain ScrollView keeps one drag
/// session across the three grouped sections; List's per-section move interaction does not.
@available(iOS 17.0, *)
struct PlayerControlsSettingsScreen: View {
    @Bindable var model: SettingsViewModel
    @State private var targetedControl: PlayerTopControl?
    @State private var targetedSection: PlayerControlLayout.Section?

    private let dragPrefix = "com.leshko.freetube.player-control:"
    private let rowHeight: CGFloat = 48

    var body: some View {
        ScrollView {
            // There are only seven controls. Keeping every row mounted avoids lazy-layout
            // handoffs while a drag moves between sections.
            VStack(alignment: .leading, spacing: 18) {
                ForEach(PlayerControlLayout.Section.allCases) { section in
                    controlSection(section)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Customize controls")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func controlSection(_ section: PlayerControlLayout.Section) -> some View {
        let controls = model.playerControlLayout.controls(in: section)

        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(targetedSection == section ? Color.primary : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { items, _ in
                    accept(items, in: section, before: controls.first)
                } isTargeted: { targeted in
                    targetedSection = targeted ? section : nil
                }

            if !controls.isEmpty {
                VStack(spacing: 0) {
                    ForEach(controls) { control in
                        controlRow(control, in: section)
                        if control != controls.last {
                            Divider()
                                .padding(.leading, 50)
                        }
                    }
                }
                .background(
                    Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .padding(.horizontal, 16)
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
