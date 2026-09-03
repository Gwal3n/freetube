import Foundation
import AVFoundation
import OSLog

/// Configures `AVAudioSession` for background-capable video playback. Call once at app launch
/// (`FreeTubeApp.init` or `RootView.onAppear`).
///
/// NOTE: For background audio to actually keep working when the app is backgrounded, the project
/// must also declare the `audio` `UIBackgroundModes` entry in `Info.plist`. Add it via Xcode →
/// target → Signing & Capabilities → Background Modes → Audio, AirPlay, and Picture in Picture.
enum AudioSessionConfigurator {
    private static let log = AppLog(subsystem: "com.leshko.freetube", category: "AudioSession")

    static func configure(allowMixing: Bool = UserPreferences().allowAudioMixing) {
        let session = AVAudioSession.sharedInstance()
        do {
            let options: AVAudioSession.CategoryOptions = allowMixing ? [.mixWithOthers] : []
            try session.setCategory(.playback, mode: .moviePlayback, options: options)
            try session.setActive(true, options: [])
            log.info("Audio session configured for .playback/.moviePlayback (mixWithOthers=\(allowMixing, privacy: .public))")
        } catch {
            log.error("Failed to configure audio session: \(String(describing: error), privacy: .public)")
        }
    }
}
