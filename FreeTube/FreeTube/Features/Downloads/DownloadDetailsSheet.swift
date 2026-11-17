import SwiftUI

import Kingfisher

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
        if let snapshot = activeSnapshot {
            switch snapshot.state {
            case .queued, .downloading, .paused: return true
            case .completed, .failed: return false
            }
        }
        return didStartDownload && downloads.localFile(for: video.id) == nil
    }

    private var isCompleted: Bool {
        if case .completed = activeSnapshot?.state { return true }
        return didStartDownload && downloads.localFile(for: video.id) != nil
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
                        Picker("Quality", selection: $selectedQuality) {
                            ForEach(videoQualities) { quality in
                                qualityLabel(quality)
                                    .tag(quality)
                            }
                        }
                        .disabled(isTransferring || isCompleted)
                    }
                } header: {
                    Text("Options")
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
            .onChange(of: activeSnapshot?.id) { _, newID in
                // External cancel clears the row; return to the Download button.
                if didStartDownload, newID == nil, !isCompleted {
                    didStartDownload = false
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func qualityLabel(_ quality: VideoQuality) -> some View {
        let title = quality == .auto
            ? String(localized: "Automatic (up to 1080p)")
            : String(localized: "Up to \(quality.displayName)")
        // One view per option — bare sibling Texts in a Picker become separate rows.
        return HStack {
            Text(title)
            Spacer(minLength: 8)
            if let bytes = model.estimatedBytes[quality] {
                Text(verbatim: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
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
