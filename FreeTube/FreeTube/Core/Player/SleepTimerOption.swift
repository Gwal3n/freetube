import Foundation

/// One-shot playback stop choices. A timer is session-only and never resumes after app relaunch.
@available(iOS 17.0, *)
enum SleepTimerOption: Equatable {
    case off
    case minutes(Int)
    case endOfVideo

    var duration: Duration? {
        switch self {
        case .minutes(let value): .seconds(value * 60)
        case .off, .endOfVideo: nil
        }
    }
}
