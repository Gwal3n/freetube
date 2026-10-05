import Foundation

/// One-shot playback stop choices. A timer is session-only and never resumes after app relaunch.
@available(iOS 17.0, *)
enum SleepTimerOption: String, CaseIterable, Identifiable {
    case off
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case endOfVideo

    var id: String { rawValue }

    var duration: Duration? {
        switch self {
        case .fifteenMinutes: .seconds(15 * 60)
        case .thirtyMinutes: .seconds(30 * 60)
        case .oneHour: .seconds(60 * 60)
        case .off, .endOfVideo: nil
        }
    }
}
