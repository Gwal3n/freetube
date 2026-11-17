import SwiftUI

import Kingfisher

/// Detailed download chooser: artwork, quality, size estimate, and an explicit Download action.
/// Caption embedding and export destinations stay out of scope until those pipelines exist.
@available(iOS 17.0, *)
struct DownloadDetailsSheet: View {
    let video: Video
    let onDownload: (VideoQuality) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultDownloadQuality") private var defaultDownloadQualityRaw = VideoQuality.p360.rawValue
    @State private var model = DownloadOptionsViewModel()
    @State private var selectedQuality: VideoQuality = .auto
    @State private var audioOnly = false

    private let videoQualities: [VideoQuality] = [
        .auto, .p2160, .p1440, .p1080, .p720, .p480, .p360, .p240, .p144
    ]

    private var effectiveQuality: VideoQuality {
        audioOnly ? .audioOnly : selectedQuality
    }

    private var estimatedLabel: String? {
        guard let bytes = model.estimatedBytes[effectiveQuality] else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
                    if !audioOnly {
                        Picker("Quality", selection: $selectedQuality) {
                            ForEach(videoQualities) { quality in
                                Text(quality == .auto
                                     ? "Automatic (up to 1080p)"
                                     : "Up to \(quality.displayName)")
                                    .tag(quality)
                            }
                        }
                    }
                } header: {
                    Text("Options")
                } footer: {
                    if model.isLoading {
                        Text("Estimating size…")
                    } else if let estimatedLabel {
                        Text("About \(estimatedLabel) for the selected option.")
                    } else if model.hasLoaded {
                        Text("Size estimate unavailable until formats load.")
                    }
                }

                Section {
                    Button {
                        onDownload(effectiveQuality)
                        dismiss()
                    } label: {
                        Text("Download")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if selectedQuality == .auto,
                   let saved = VideoQuality(rawValue: defaultDownloadQualityRaw),
                   saved != .audioOnly {
                    selectedQuality = saved == .auto ? .auto : saved
                }
                await model.loadEstimates(for: video)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
