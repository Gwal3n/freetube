import SwiftUI
import UIKit

@available(iOS 17.0, *)
struct DownloadTransferRow: View {
    let snapshot: DownloadTaskSnapshot
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: MediaStyle.spacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.title)
                    .font(MediaStyle.title)
                    .lineLimit(2)
                progress
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

@available(iOS 17.0, *)
struct DownloadedVideoRow<MenuContent: View>: View {
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
        HStack(spacing: MediaStyle.spacing) {
            thumbnail
                .frame(width: 96, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(MediaStyle.title)
                    .lineLimit(2)
                if !item.channelName.isEmpty {
                    Text(item.channelName)
                        .font(MediaStyle.metadata)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                    if let duration = item.duration {
                        Text(verbatim: "• \(durationText(duration))")
                    }
                }
                .font(MediaStyle.tertiaryMetadata)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !isSelecting { menu() }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isSelecting { onPlay() }
        }
        .swipeActions {
            if !isSelecting {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = item.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            Color.secondary.opacity(0.12)
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
