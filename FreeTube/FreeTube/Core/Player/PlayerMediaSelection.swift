import AVFoundation
import Foundation

/// Applies the app's caption and original-audio policy to a newly installed player item.
/// This owns only AVFoundation media selection; PlayerStateManager still owns the item swap.
@available(iOS 17.0, *)
@MainActor
enum PlayerMediaSelection {
    static func configure(
        item: AVPlayerItem,
        on player: AVQueuePlayer,
        originalAudioLanguageCode: String?,
        log: AppLog
    ) {
        disableLegibleMediaSelection(on: item)
        selectOriginalAudio(
            on: item,
            player: player,
            languageCode: originalAudioLanguageCode,
            log: log
        )
    }

    /// Automatic caption selection is disabled on the player, but an item may also contain a
    /// default or forced legible track. Clear that option after its media group becomes available.
    private static func disableLegibleMediaSelection(on item: AVPlayerItem) {
        Task { @MainActor [weak item] in
            guard let item else { return }
            do {
                guard let group = try await item.asset.loadMediaSelectionGroup(for: .legible) else {
                    return
                }
                item.select(nil, in: group)
            } catch {
                // Most progressive assets have no legible group.
            }
        }
    }

    /// Prefer the soundtrack's source language, then an explicitly labelled original option,
    /// then the manifest default. A replacement item is never configured after it was detached.
    private static func selectOriginalAudio(
        on item: AVPlayerItem,
        player: AVQueuePlayer,
        languageCode: String?,
        log: AppLog
    ) {
        Task { @MainActor [weak item, weak player] in
            guard let item, let player else { return }
            do {
                guard let group = try await item.asset.loadMediaSelectionGroup(for: .audible),
                      player.currentItem === item else { return }

                let languageMatch = languageCode.flatMap { code in
                    group.options.first { audioOption($0, matches: code) }
                }
                let originalLabel = group.options.first {
                    $0.displayName.localizedCaseInsensitiveContains("original")
                }
                guard let selection = languageMatch ?? originalLabel ?? group.defaultOption else {
                    log.notice(
                        "Did not force HLS audio selection: sourceLanguage=\(languageCode ?? "unknown", privacy: .public) options=\(group.options.count, privacy: .public)"
                    )
                    return
                }

                item.select(selection, in: group)
                log.info(
                    "Selected HLS audio option=\(selection.displayName, privacy: .public) sourceLanguage=\(languageCode ?? "unknown", privacy: .public) metadataMatch=\(languageMatch != nil, privacy: .public) options=\(group.options.count, privacy: .public)"
                )
            } catch {
                // Absence is expected for progressive assets.
            }
        }
    }

    private nonisolated static func audioOption(
        _ option: AVMediaSelectionOption,
        matches languageCode: String
    ) -> Bool {
        let requested = normalizedLanguageIdentifier(languageCode)
        guard !requested.isEmpty else { return false }
        return [option.extendedLanguageTag, option.locale?.identifier]
            .compactMap { $0 }
            .map(normalizedLanguageIdentifier)
            .contains {
                $0 == requested
                    || $0.hasPrefix(requested + "-")
                    || requested.hasPrefix($0 + "-")
            }
    }

    private nonisolated static func normalizedLanguageIdentifier(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}
