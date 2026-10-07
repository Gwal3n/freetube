import Foundation
import Observation
import SwiftUI

/// Holds the previous app visit boundary for the current foreground session. A background-to-
/// foreground return starts a new visit; temporary inactive states such as sheets do not.
@available(iOS 17.0, *)
@Observable
@MainActor
final class AppVisitState {
    private static let lastVisitKey = "com.leshko.freetube.lastAppVisitAt"

    private(set) var previousVisitAt: Date?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var wasBackgrounded = false

    init(defaults: UserDefaults = .standard, now: Date = .now) {
        self.defaults = defaults
        previousVisitAt = defaults.object(forKey: Self.lastVisitKey) as? Date
        defaults.set(now, forKey: Self.lastVisitKey)
    }

    func scenePhaseChanged(_ phase: ScenePhase, now: Date = .now) {
        switch phase {
        case .background:
            defaults.set(now, forKey: Self.lastVisitKey)
            wasBackgrounded = true
        case .active where wasBackgrounded:
            previousVisitAt = defaults.object(forKey: Self.lastVisitKey) as? Date
            defaults.set(now, forKey: Self.lastVisitKey)
            wasBackgrounded = false
        default:
            break
        }
    }
}
