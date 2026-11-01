import SwiftUI
import UIKit

/// Shared visual roles for media browsing. Screen containers own outer margins.
enum MediaStyle {
    static let spacing: CGFloat = 12
    static let labelSpacing: CGFloat = 2
    static let thumbnailRadius: CGFloat = 8
    static let actionSize: CGFloat = 44
    static let placeholderFill = Color.secondary.opacity(0.12)
    static let pageBackground = Color(uiColor: .systemBackground)
    static let cardHorizontalPadding: CGFloat = 16
    static let cardContentSpacing: CGFloat = 8
    static let cardTopPadding: CGFloat = 4
    static let cardBottomPadding: CGFloat = 14
    static let cardAvatarSize: CGFloat = 36
    static let listRowInsets = EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 8)

    /// Used by compact video rows and their loading placeholders, so a loading row keeps
    /// the same geometry when its video arrives or Dynamic Type changes.
    static func compactVideoThumbnailSize(for dynamicTypeSize: DynamicTypeSize) -> CGSize {
        dynamicTypeSize.isAccessibilitySize
            ? CGSize(width: 104, height: 58.5)
            : CGSize(width: 144, height: 81)
    }

    static func mediaTitleLineLimit(for dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 4 : 2
    }
}

/// A deliberately small motion vocabulary for non-interactive interface changes.
/// Player gestures keep their own spring physics because those animations follow the finger.
enum InterfaceMotion {
    static let quick = Animation.snappy(duration: 0.22)
    static let content = Animation.smooth(duration: 0.24)
    static let notice = Animation.smooth(duration: 0.25)
}

extension View {
    /// Applies the shared browsing-row geometry at the List's immediate child boundary.
    func mediaListRow() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(MediaStyle.listRowInsets)
    }
}
