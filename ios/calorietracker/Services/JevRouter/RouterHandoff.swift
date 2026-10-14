import Foundation
import Observation

/// One-shot handoffs from a Coach bubble into an existing review screen.
/// The router never logs food or a workout by itself.
@MainActor
@Observable
final class RouterHandoff {
    static let shared = RouterHandoff()

    /// Home consumes this and runs the typed-food flow.
    var pendingFoodText: String?
    /// Train consumes this and opens today's program session, when there is one.
    var pendingOpenTodayWorkout = false

    private init() {}
}
