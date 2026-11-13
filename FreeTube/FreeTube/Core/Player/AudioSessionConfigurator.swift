import Foundation
import AVFoundation
import OSLog

/// Configures `.playback` / `.moviePlayback`. Activate on play; requires the `audio` background mode.
enum AudioSessionConfigurator {
    private static let log = AppLog(subsystem: "com.leshko.freetube", category: "AudioSession")

    static func configure(
        allowMixing: Bool = UserPreferences().allowAudioMixing,
        activate: Bool = false
    ) {
        let session = AVAudioSession.sharedInstance()
        do {
            let options: AVAudioSession.CategoryOptions = allowMixing ? [.mixWithOthers] : []
            try session.setCategory(.playback, mode: .moviePlayback, options: options)
            if activate {
                try session.setActive(true, options: [])
            }
            log.info("Audio session configured for .playback/.moviePlayback (mixWithOthers=\(allowMixing, privacy: .public) active=\(activate, privacy: .public))")
        } catch {
            log.error("Failed to configure audio session: \(String(describing: error), privacy: .public)")
        }
    }
}
