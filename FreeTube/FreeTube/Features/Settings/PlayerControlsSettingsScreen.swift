import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Live, cross-section reordering for optional player controls. iOS supports DropDelegate's
/// hover callbacks but not SwiftUI's drag-session-end observer, so each visible move is retained.
@available(iOS 17.0, *)
struct PlayerControlsSettingsScreen: View {
    @Bindable var model: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggedControl: PlayerTopControl?
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
        .onDisappear { cancelDrag() }
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
                .onDrop(of: [.plainText], delegate: ControlDropDelegate(
                    isActive: { draggedControl != nil },
                    onEnter: { _ in
                        targetedSection = section
                        hover(in: section, before: model.playerControlLayout.controls(in: section).first)
                    },
                    onExit: {
                        if targetedSection == section { targetedSection = nil }
                    },
                    onDrop: { finishDrag() }
                ))

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
        .onDrag {
            draggedControl = control
            return NSItemProvider(object: NSString(string: dragPrefix + control.rawValue))
        } preview: {
            Label(control.displayName, systemImage: control.systemImage)
                .font(.subheadline)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .onDrop(of: [.plainText], delegate: ControlDropDelegate(
            isActive: { draggedControl != nil },
            onEnter: { locationY in
                hover(over: control, in: section, at: locationY)
            },
            onExit: {},
            onDrop: { finishDrag() }
        ))
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

    private func hover(over target: PlayerTopControl, in section: PlayerControlLayout.Section, at locationY: CGFloat) {
        guard let draggedControl, draggedControl != target else { return }
        let controls = model.playerControlLayout.controls(in: section)
        guard let targetIndex = controls.firstIndex(of: target) else { return }
        let afterTarget = controls.indices.contains(targetIndex + 1) ? controls[targetIndex + 1] : nil
        let insertionTarget: PlayerTopControl?
        if let sourceIndex = controls.firstIndex(of: draggedControl) {
            // Crossing a row in the same section moves past it in the drag direction. Do not
            // recalculate this every frame: a moved row would otherwise bounce under the finger.
            insertionTarget = sourceIndex < targetIndex ? afterTarget : target
        } else {
            insertionTarget = locationY < rowHeight / 2 ? target : afterTarget
        }
        hover(in: section, before: insertionTarget)
    }

    private func hover(in section: PlayerControlLayout.Section, before target: PlayerTopControl?) {
        guard let draggedControl else { return }
        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
            model.movePlayerControl(draggedControl, to: section, before: target)
        }
    }

    private func finishDrag() -> Bool {
        guard draggedControl != nil else { return false }
        cancelDrag()
        return true
    }

    private func cancelDrag() {
        draggedControl = nil
        targetedSection = nil
    }
}

/// `dropEntered` is the live reorder point; `performDrop` only ends the drag session.
@available(iOS 17.0, *)
@MainActor
private struct ControlDropDelegate: DropDelegate {
    let isActive: () -> Bool
    let onEnter: (CGFloat) -> Void
    let onExit: () -> Void
    let onDrop: () -> Bool

    func validateDrop(info: DropInfo) -> Bool { isActive() }

    func dropEntered(info: DropInfo) { onEnter(info.location.y) }

    func dropExited(info: DropInfo) { onExit() }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool { onDrop() }
}
