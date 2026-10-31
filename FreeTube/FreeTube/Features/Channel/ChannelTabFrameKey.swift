import SwiftUI

/// Measured frame of each tab label, keyed by `ChannelProfileTab.id`.
@available(iOS 17.0, *)
struct ChannelTabFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
