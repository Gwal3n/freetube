import SwiftUI
import UIKit

@available(iOS 17.0, *)
struct DownloadTransferRow: View {
    let snapshot: DownloadTaskSnapshot
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: MediaStyle.spacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                    .appFont(.subheadline, weight: .semibold)
                    .lineLimit(2)
                progress
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if case .failed = snapshot.state {
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.primary)
                        .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityLabel("Retry download")
            } else {
                Button(role: .destructive, action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: MediaStyle.actionSize, height: MediaStyle.actionSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ResponsiveButtonStyle())
                .accessibilityLabel("Cancel download")
            }
        }
    }

    @ViewBuilder
    private var progress: some View {
        switch snapshot.state {
        case .queued:
            statusText("Queued")
        case .downloading(let value):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: value)
                Text("\(Int(value * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Downloading")
            .accessibilityValue("\(Int(value * 100)) percent")
        case .paused:
            statusText("Paused")
        case .completed:
            Text("Completed").font(.caption).foregroundStyle(.green)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 2) {
                Text("Download failed")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

@available(iOS 17.0, *)
struct DownloadedVideoRow<MenuContent: View>: View {
    @Environment(PlayerStateManager.self) private var player
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var launchAnchor = VideoLaunchAnchor()
    let item: SavedItem
    let isSelecting: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void
    private let menu: () -> MenuContent

    init(
        item: SavedItem,
        isSelecting: Bool,
        onPlay: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder menu: @escaping () -> MenuContent
    ) {
        self.item = item
        self.isSelecting = isSelecting
        self.onPlay = onPlay
        self.onDelete = onDelete
        self.menu = menu
    }

    var body: some View {
        HStack(alignment: .top, spacing: MediaStyle.spacing) {
            thumbnail
                .frame(width: thumbnailSize.width, height: thumbnailSize.height)
                .overlay(alignment: .bottomTrailing) {
                    if let duration = item.duration, duration.isFinite, duration > 0 {
                        Text(durationText(duration))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
                            .padding(5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius, style: .continuous))
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { frame in
                    launchAnchor.frame = frame
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .appFont(.subheadline, weight: .semibold)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                if !item.channelName.isEmpty {
                    Text(item.channelName)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                .appFont(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isSelecting { menu() }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isSelecting {
                player.prepareLaunch(for: item.videoID, from: launchAnchor.frame)
                onPlay()
            }
        }
        .swipeActions {
            if !isSelecting {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .mediaListRow()
    }

    private var thumbnailSize: CGSize {
        dynamicTypeSize.isAccessibilitySize
            ? CGSize(width: 104, height: 58.5)
            : CGSize(width: 144, height: 81)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = item.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            MediaStyle.placeholderFill
                .overlay { Image(systemName: "play.rectangle").foregroundStyle(.secondary) }
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds) }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
