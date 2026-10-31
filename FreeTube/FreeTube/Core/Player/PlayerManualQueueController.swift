import Foundation
import UIKit

/// Owns the user's explicit queue, its persistence, and short-lived undo notices.
/// Playback handoff stays with PlayerStateManager.
@available(iOS 17.0, *)
@MainActor
@Observable
final class PlayerManualQueueController {
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let offersUndo: Bool
    }

    private(set) var items: [Video] = PlayerManualQueueStore.restore()
    private(set) var notice: Notice?
    @ObservationIgnored private var noticeDismissTask: Task<Void, Never>?
    @ObservationIgnored private var undoAction: (() -> Void)?

    // MARK: - Queue mutations

    @discardableResult
    func enqueueNext(_ video: Video, currentVideoID: String?) -> Bool {
        guard video.id != currentVideoID, !VideoBlocklist.shared.blocks(video) else { return false }
        items = PlayerManualQueueStore.insertingNext(video, into: items)
        persist()
        showNotice(message: "Playing next")
        return true
    }

    @discardableResult
    func enqueue(_ video: Video, currentVideoID: String?) -> Bool {
        guard video.id != currentVideoID,
              !VideoBlocklist.shared.blocks(video),
              !items.contains(where: { $0.id == video.id }) else { return false }
        items = PlayerManualQueueStore.appending(video, to: items)
        persist()
        showNotice(message: "Added to queue")
        return true
    }

    @discardableResult
    func remove(_ videoID: String) -> Bool {
        guard items.contains(where: { $0.id == videoID }) else { return false }
        items = PlayerManualQueueStore.removing(videoID, from: items)
        persist()
        return true
    }

    func removeWithUndo(_ videoID: String) {
        guard let index = items.firstIndex(where: { $0.id == videoID }) else { return }
        let removedVideo = items.remove(at: index)
        persist()
        showNotice(message: "Removed") { [weak self] in
            guard let self, !self.items.contains(where: { $0.id == removedVideo.id }) else { return }
            self.items = PlayerManualQueueStore.restoring(removedVideo, at: index, to: self.items)
            self.persist()
        }
    }

    func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        persist()
    }

    func clearWithUndo() {
        guard !items.isEmpty else { return }
        let removedVideos = items
        items.removeAll()
        persist()
        showNotice(message: "Queue cleared") { [weak self] in
            guard let self else { return }
            self.items = PlayerManualQueueStore.restoring(removedVideos, to: self.items)
            self.persist()
        }
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard let reordered = PlayerManualQueueStore.reordered(
            items,
            fromOffsets: offsets,
            toOffset: destination,
            isBlocked: { VideoBlocklist.shared.blocks($0) }
        ) else { return }
        items = reordered
        persist()
    }

    // MARK: - Notice lifecycle

    func showNotice(message: String, undoAction: (() -> Void)? = nil, haptic: Bool = true) {
        let newNotice = Notice(message: message, offersUndo: undoAction != nil)
        notice = newNotice
        self.undoAction = undoAction
        if haptic { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        noticeDismissTask?.cancel()
        let displayDuration: Duration = undoAction == nil ? .seconds(1.4) : .seconds(2)
        noticeDismissTask = Task { [weak self] in
            try? await Task.sleep(for: displayDuration)
            guard !Task.isCancelled, self?.notice?.id == newNotice.id else { return }
            self?.notice = nil
            self?.undoAction = nil
        }
    }

    func undoNotice() {
        guard let action = undoAction else { return }
        noticeDismissTask?.cancel()
        undoAction = nil
        notice = nil
        action()
    }

    private func persist() {
        PlayerManualQueueStore.persist(items)
    }
}
