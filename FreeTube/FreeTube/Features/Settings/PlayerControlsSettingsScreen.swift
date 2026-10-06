import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Live, cross-section reordering for optional player controls. Hover changes are kept in a local
/// draft so dragging does not write UserDefaults and rebuild the player on every crossed row.
/// SwiftUI has no reliable drag-session-end callback here, so the visible draft is also committed
/// on navigation away if the drag ended outside a drop target.
@available(iOS 17.0, *)
struct PlayerControlsSettingsScreen: View {
    @Bindable var model: SettingsViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggedControl: PlayerTopControl?
    @State private var draftLayout: PlayerControlLayout?

    private let dragPrefix = "com.leshko.freetube.player-control:"
    private let rowHeight: CGFloat = 48

    private var displayedLayout: PlayerControlLayout {
        draftLayout ?? model.playerControlLayout
    }

    var body: some View {
        ScrollView {
            // There are only seven controls. Keeping every row mounted avoids lazy-layout
            // handoffs while a drag moves between sections.
            VStack(alignment: .leading, spacing: 18) {
                ForEach(PlayerControlLayout.Section.allCases) { section in
                    controlSection(section)
                }
                if displayedLayout.moreMenu.count > 1 {
                    menuDividerSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Customize controls")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { endDrag() }
    }

    private func controlSection(_ section: PlayerControlLayout.Section) -> some View {
        let controls = displayedLayout.controls(in: section)

        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: section.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onDrop(of: [.plainText], delegate: ControlDropDelegate(
                    isActive: { draggedControl != nil },
                    onEnter: { _ in
                        hover(in: section, before: displayedLayout.controls(in: section).first)
                    },
                    onExit: {},
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
            if draftLayout == nil { draftLayout = model.playerControlLayout }
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
            moveImmediately(control, to: .onPlayer)
        }
        .accessibilityAction(named: "Move to More menu") {
            moveImmediately(control, to: .moreMenu)
        }
        .accessibilityAction(named: "Hide control") {
            moveImmediately(control, to: .hidden)
        }
    }

    private var menuDividerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("More menu separators")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(displayedLayout.moreMenu.dropFirst())) { control in
                    Toggle(isOn: dividerBinding(before: control)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: control.displayName)
                                .font(.subheadline)
                            Text("Divider above")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color(uiColor: .label))
                    .frame(minHeight: rowHeight)
                    .padding(.horizontal, 16)

                    if control != displayedLayout.moreMenu.last {
                        Divider()
                            .padding(.leading, 16)
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

    private func moveImmediately(_ control: PlayerTopControl, to section: PlayerControlLayout.Section) {
        // Accessibility actions are discrete moves; finish any visible draft first so a later
        // drag dismissal cannot overwrite the VoiceOver user's choice.
        endDrag()
        model.movePlayerControl(control, to: section)
    }

    private func hover(over target: PlayerTopControl, in section: PlayerControlLayout.Section, at locationY: CGFloat) {
        guard let draggedControl, draggedControl != target else { return }
        let controls = displayedLayout.controls(in: section)
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
        var layout = displayedLayout
        layout.move(draggedControl, to: section, before: target)
        guard layout != displayedLayout else { return }
        withAnimation(reduceMotion ? nil : InterfaceMotion.quick) {
            draftLayout = layout
        }
    }

    private func finishDrag() -> Bool {
        guard draggedControl != nil else { return false }
        endDrag()
        return true
    }

    private func endDrag() {
        if let draftLayout, draftLayout != model.playerControlLayout {
            model.playerControlLayout = draftLayout
        }
        draftLayout = nil
        draggedControl = nil
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
