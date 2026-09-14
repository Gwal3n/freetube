import SwiftUI

/// Shared visual roles for media browsing. Screen containers own outer margins.
enum MediaStyle {
    static let spacing: CGFloat = 12
    static let thumbnailRadius: CGFloat = 8
    static let actionSize: CGFloat = 44
    static let title: Font = .subheadline.weight(.semibold)
    static let metadata: Font = .caption
    static let tertiaryMetadata: Font = .caption2
    static let placeholderFill = Color.secondary.opacity(0.12)
    static let cardHorizontalPadding: CGFloat = 16
    static let listRowInsets = EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 8)
}

/// A deliberately small motion vocabulary for non-interactive interface changes.
/// Player gestures keep their own spring physics because those animations follow the finger.
enum InterfaceMotion {
    static let quick = Animation.snappy(duration: 0.22)
    static let content = Animation.smooth(duration: 0.24)
    static let notice = Animation.smooth(duration: 0.25)
}
