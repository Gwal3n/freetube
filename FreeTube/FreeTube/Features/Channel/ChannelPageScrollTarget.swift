import CoreGraphics

/// A token makes the same offset a new request for a page mounted later by the lazy pager.
struct ChannelPageScrollTarget: Equatable {
    var y: CGFloat
    var token: Int
}
