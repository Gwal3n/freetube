import CoreGraphics

/// Continuous sheet positioning for chapter / live-chat / playlist portrait sheets.
///
/// The sheet's visible top is `expansionTravel * (1 - expansion) + dismiss`. Mapping every drag
/// sample through that single axis keeps motion 1:1 with the finger — including across the
/// collapsed (player-bottom) detent — and only snaps when the gesture ends.
@available(iOS 17.0, *)
enum PlayerSheetDragMath {
    struct Position: Equatable {
        var expansion: CGFloat
        var dismiss: CGFloat

        static func top(expansion: CGFloat, dismiss: CGFloat, travel: CGFloat) -> CGFloat {
            max(0, travel) * (1 - expansion) + max(0, dismiss)
        }
    }

    enum Settlement {
        case expanded
        case collapsed
        case dismiss
    }

    /// Finger-following position. Clamps only the fully-expanded ceiling so the sheet cannot
    /// travel above the viewport; the collapsed detent is never a hard stop while dragging.
    static func position(
        startExpansion: CGFloat,
        startDismiss: CGFloat = 0,
        translationHeight: CGFloat,
        expansionTravel: CGFloat
    ) -> Position {
        let travel = max(1, expansionTravel)
        let startTop = Position.top(expansion: startExpansion, dismiss: startDismiss, travel: travel)
        let newTop = max(0, startTop + translationHeight)
        if newTop >= travel {
            return Position(expansion: 0, dismiss: newTop - travel)
        }
        return Position(expansion: 1 - newTop / travel, dismiss: 0)
    }

    /// Detent choice from the projected finger end. Past the collapsed edge by
    /// `dismissThreshold` closes the sheet; otherwise snap to expanded or collapsed.
    static func settlement(
        startExpansion: CGFloat,
        startDismiss: CGFloat = 0,
        predictedTranslationHeight: CGFloat,
        expansionTravel: CGFloat,
        dismissThreshold: CGFloat
    ) -> Settlement {
        let travel = max(1, expansionTravel)
        let startTop = Position.top(expansion: startExpansion, dismiss: startDismiss, travel: travel)
        let projectedTop = max(0, startTop + predictedTranslationHeight)
        if projectedTop >= travel + dismissThreshold {
            return .dismiss
        }
        return projectedTop < travel * 0.5 ? .expanded : .collapsed
    }
}
