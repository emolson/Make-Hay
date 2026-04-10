//
//  BackgroundHealthMonitorProtocol.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/20/26.
//

import BackgroundTasks
import Foundation

/// Snapshot produced by a single evaluation cycle: health metrics, blocking decision,
/// and timestamp.
///
/// **Why a dedicated type?** Previously the background monitor and dashboard each ran
/// their own independent fetch → evaluate → shield-update cycle. This struct lets the
/// monitor return its result so the dashboard can display the same data that drove the
/// shield decision — single source of truth, no duplicate HealthKit round-trips.
///
/// **Why `Codable`?** Persisted to `SharedStorage` as JSON so the dashboard can seed
/// its UI instantly on cold start without waiting for the first async sync.
struct EvaluationResult: Sendable, Codable {
    var steps: Int
    var activeEnergy: Double
    var exerciseMinutesByGoalId: [UUID: Int]
    var shouldBlock: Bool
    var timestamp: Date
}

/// Protocol defining the interface for background HealthKit observation.
///
/// **Why a separate protocol?** Decouples the observer/background-delivery concern from
/// data-fetching (`HealthServiceProtocol`). The monitor registers `HKObserverQuery`s and
/// `enableBackgroundDelivery` so HealthKit can wake the app when health data changes,
/// allowing goal evaluation and shield updates without user interaction.
///
/// **Reliability model:** Implementations provide a layered wake strategy:
/// 1. `HKObserverQuery` (fires on every HealthKit write when app is in memory)
/// 2. `enableBackgroundDelivery(.immediate)` (wakes terminated app on data arrival)
/// 3. `BGAppRefreshTask` (orthogonal wake path independent of HealthKit daemon)
/// 4. Foreground sync via `syncNow()` (catch-all on every app open)
protocol BackgroundHealthMonitorProtocol: Actor {
    /// Registers `HKObserverQuery` instances, enables background delivery, and schedules
    /// the `BGAppRefreshTask` for all tracked health types (steps, active energy,
    /// exercise time).
    ///
    /// Should be called once during app startup. Observer queries and
    /// `enableBackgroundDelivery` registrations do not persist across app terminations,
    /// so this must be called on every launch.
    func startMonitoring() async

    /// Stops all observer queries and disables background delivery.
    ///
    /// Typically called only during testing or app teardown.
    func stopMonitoring() async

    /// Performs an immediate, foreground-priority evaluation of health goals and updates
    /// Screen Time shields accordingly.
    ///
    /// **Why expose this?** HealthKit background delivery is throttled by iOS based on
    /// battery, thermal state, and app-usage patterns. When the user opens the app and
    /// taps "Refresh Sync," this method bypasses the observer cadence and fetches the
    /// latest health data right away, ensuring shields reflect current progress.
    ///
    /// Uses the same evaluation pipeline as background observer callbacks so shield
    /// decisions are always consistent.
    ///
    /// - Returns: The evaluation result containing health metrics and blocking decision.
    @discardableResult
    func syncNow(reason: String) async throws -> EvaluationResult

    /// Handles a `BGAppRefreshTask` wake — the orthogonal Layer 3 background wake path.
    ///
    /// Re-registers observer queries (guards against silent invalidation after HealthKit
    /// daemon restart), runs a full evaluation, and schedules the next refresh.
    ///
    /// - Parameter task: The background task provided by the system.
    func handleBackgroundRefresh(task: BGAppRefreshTask) async
}

extension BackgroundHealthMonitorProtocol {
    @discardableResult
    func syncNow() async throws -> EvaluationResult {
        try await syncNow(reason: "unspecified")
    }
}
