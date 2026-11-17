import SwiftUI

import Kingfisher

/// Detailed download chooser: artwork, quality with size estimates, and an explicit Download
/// action that keeps the sheet open to show transfer progress. Dismissing (swipe or Close)
/// leaves the download running in Downloads; only Cancel download stops it. Caption embedding
/// is omitted — downloads do not mux captions today. Container labels appear only when format
/// mime metadata already supplies them.
@available(iOS 17.0, *)
struct DownloadDetailsSheet: View {
    let video: Video
    let onDownload: (VideoQuality) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultDownloadQuality") private var defaultDownloadQualityRaw = VideoQuality.p360.rawValue
    @State private var model = DownloadOptionsViewModel()
    @State private var selectedQuality: VideoQuality = .auto
    @State private var audioOnly = false
    @State private var didStartDownload = false
    @State private var downloads = DownloadManager.shared

    private let videoQualities: [VideoQuality] = [
        .auto, .p2160, .p1440, .p1080, .p720, .p480, .p360, .p240, .p144
    ]

    private var effectiveQuality: VideoQuality {
        audioOnly ? .audioOnly : selectedQuality
    }

    private var activeSnapshot: DownloadTaskSnapshot? {
        downloads.activeTasks.first { $0.videoID == video.id }
    }

    private var transferProgress: Double? {
        if case .downloading(let value) = activeSnapshot?.state { return value }
        return downloads.progressByVideoID[video.id]
    }

    private var isTransferring: Bool {
        guard let snapshot = activeSnapshot else {
            return didStartDownload && downloads.localFile(for: video.id) == nil
        }
        switch snapshot.state {
        case .queued, .downloading, .paused: return true
        case .completed, .failed: return false
        }
    }

    private var isCompleted: Bool {
        downloads.localFile(for: video.id) != nil
            && (didStartDownload || activeSnapshot != nil)
    }

    private var selectedContainer: String? {
        model.containerByQuality[effectiveQuality]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top, spacing: 14) {
                        KFImage(video.thumbnailURL)
                            .thumbnail(size: CGSize(width: 160, height: 90)) {
                                MediaStyle.placeholderFill
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 128, height: 72)
                            .background(MediaStyle.placeholderFill)
                            .clipShape(RoundedRectangle(cornerRadius: MediaStyle.thumbnailRadius, style: .continuous))
                            .mediaArtworkOutline()

                        VStack(alignment: .leading, spacing: 4) {
                            Text(video.title)
                                .appFont(.subheadline, weight: .semibold)
                                .lineLimit(3)
                            if !video.channelName.isEmpty {
                                Text(video.channelName)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if !video.durationString.isEmpty {
                                Text(verbatim: video.durationString)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                Section {
                    Toggle("Audio only", isOn: $audioOnly)
                        .disabled(isTransferring || isCompleted)
                    if !audioOnly {
                        ForEach(videoQualities) { quality in
                            qualityRow(quality)
                        }
                    } else {
                        qualityRow(.audioOnly)
                    }
                } header: {
                    Text("Options")
                } footer: {
                    optionsFooter
                }

                Section {
                    downloadAction
                }
            }
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isCompleted ? "Done" : "Close") {
                        dismiss()
                    }
                }
            }
            .task {
                if selectedQuality == .auto,
                   let saved = VideoQuality(rawValue: defaultDownloadQualityRaw),
                   saved != .audioOnly {
                    selectedQuality = saved
                }
                await model.loadEstimates(for: video)
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func qualityRow(_ quality: VideoQuality) -> some View {
        let isSelected = effectiveQuality == quality
        Button {
            if quality == .audioOnly {
                audioOnly = true
            } else {
                audioOnly = false
                selectedQuality = quality
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(for: quality))
                        .foregroundStyle(.primary)
                    if let container = model.containerByQuality[quality] {
                        Text(verbatim: container)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let bytes = model.estimatedBytes[quality] {
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if model.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTransferring || isCompleted)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func title(for quality: VideoQuality) -> String {
        switch quality {
        case .auto: return String(localized: "Automatic (up to 1080p)")
        case .audioOnly: return String(localized: "Audio only")
        default: return String(localized: "Up to \(quality.displayName)")
        }
    }

    @ViewBuilder
    private var optionsFooter: some View {
        if model.isLoading {
            Text("Estimating size…")
        } else if let selectedContainer {
            Text("Selected option uses \(selectedContainer).")
        } else if model.hasLoaded, model.estimatedBytes.isEmpty {
            Text("Size estimate unavailable until formats load.")
        }
    }

    @ViewBuilder
    private var downloadAction: some View {
        if isCompleted {
            HStack {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        } else if isTransferring {
            VStack(alignment: .leading, spacing: 10) {
                if let transferProgress {
                    ProgressView(value: transferProgress)
                    Text(verbatim: "\(Int((transferProgress * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Starting download…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Cancel download", role: .destructive) {
                    downloads.cancel(videoID: video.id)
                    didStartDownload = false
                }
            }
            .padding(.vertical, 4)
        } else {
            Button {
                didStartDownload = true
                onDownload(effectiveQuality)
            } label: {
                Text("Download")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
