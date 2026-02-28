//
//  BackgroundHealthMonitor.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/20/26.
//

import Foundation
import HealthKit
import os.log

/// Actor that registers `HKObserverQuery` instances and enables `enableBackgroundDelivery`
/// for all tracked health types so HealthKit can wake the app in the background when health
/// data changes.
///
/// **Why a separate actor?** Keeps observer/background-delivery concerns decoupled from
/// data-fetching (`HealthService`) and from shield management (`BlockerService`). This actor
/// coordinates the two: when HealthKit delivers a background update, it re-fetches health data,
/// evaluates goals via `GoalBlockingEvaluator`, and updates shields — all without the user
/// opening the app.
///
/// **Why Actor?** Observer query callbacks arrive on arbitrary HealthKit background threads.
/// Actor isolation serializes access to the stored query references and prevents data races
/// during concurrent background wakes.
actor BackgroundHealthMonitor: BackgroundHealthMonitorProtocol {

    // MARK: - Dependencies

    private let healthStore: HKHealthStore
    private let healthService: any HealthServiceProtocol
    private let blockerService: any BlockerServiceProtocol

    // MARK: - Private State

    /// Running observer queries, stored so they can be stopped during teardown.
    private var observerQueries: [HKObserverQuery] = []

    /// Whether monitoring has been started. Prevents duplicate registration.
    private var isMonitoring: Bool = false

    /// Logger for background health monitoring events.
    private static let logger = Logger(
        subsystem: "com.ethanolson.Make-Hay",
        category: "BackgroundHealthMonitor"
    )

    // MARK: - Health Types

    /// The set of `HKSampleType`s we observe for background delivery.
    ///
    /// **Why all three?** The user can configure goals based on steps, active energy,
    /// or exercise minutes. Observing all three ensures any relevant HealthKit write
    /// triggers a re-evaluation, not just step updates.
    private static let observedTypes: [HKSampleType] = {
        [
            HKQuantityType.quantityType(forIdentifier: .stepCount),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)
        ].compactMap { $0 }
    }()

    // MARK: - Initialization

    /// Creates a new `BackgroundHealthMonitor`.
    /// - Parameters:
    ///   - healthStore: The shared `HKHealthStore` instance (same one used by `HealthService`).
    ///   - healthService: Service for fetching current health data.
    ///   - blockerService: Service for updating Screen Time shields.
    ///
    /// **Why inject the store separately?** The monitor needs direct access to the store
    /// for `execute(_:)`, `stop(_:)`, and `enableBackgroundDelivery(for:frequency:)` — APIs
    /// that live on `HKHealthStore`, not on our `HealthServiceProtocol`.
    init(
        healthStore: HKHealthStore,
        healthService: any HealthServiceProtocol,
        blockerService: any BlockerServiceProtocol
    ) {
        self.healthStore = healthStore
        self.healthService = healthService
        self.blockerService = blockerService
    }

    // MARK: - BackgroundHealthMonitorProtocol

    /// Registers observer queries and enables background delivery for each tracked health type.
    ///
    /// Observer queries and background delivery registrations do **not** persist across app
    /// terminations, so this must be called on every app launch. Calling it multiple times
    /// is safe — duplicate registrations are guarded by `isMonitoring`.
    func startMonitoring() async {
        guard !isMonitoring else {
            Self.logger.debug("Background health monitoring already active — skipping.")
            return
        }

        Self.logger.info("Starting background health monitoring for \(Self.observedTypes.count) types.")

        for sampleType in Self.observedTypes {
            registerObserverQuery(for: sampleType)
            await enableBackgroundDelivery(for: sampleType)
        }

        isMonitoring = true
        Self.logger.info("Background health monitoring started successfully.")
    }

    /// Stops all observer queries and disables background delivery.
    func stopMonitoring() async {
        Self.logger.info("Stopping background health monitoring.")

        for query in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()

        do {
            try await healthStore.disableAllBackgroundDelivery()
            Self.logger.info("All background deliveries disabled.")
        } catch {
            Self.logger.error("Failed to disable background deliveries: \(error.localizedDescription)")
        }

        isMonitoring = false
    }

    // MARK: - Private Helpers

    /// Registers an `HKObserverQuery` for the given sample type.
    ///
    /// **How this works:** When HealthKit receives new data for this type (e.g., the pedometer
    /// writes new step samples), it invokes the `updateHandler`. If the app is in the background,
    /// HealthKit briefly wakes it (thanks to `enableBackgroundDelivery`), giving us ~30 seconds
    /// to evaluate goals and update shields.
    ///
    /// **Critical:** The `completionHandler` **must** be called when processing is done.
    /// Failing to call it prevents future background deliveries.
    private func registerObserverQuery(for sampleType: HKSampleType) {
        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) {
            [weak self] _, completionHandler, error in

            if let error {
                Self.logger.error(
                    "Observer query error for \(sampleType.identifier): \(error.localizedDescription)"
                )
                completionHandler()
                return
            }

            Self.logger.info("Observer query fired for \(sampleType.identifier)")

            guard let self else {
                completionHandler()
                return
            }

            // Bridge from the callback-based HKObserverQuery into async/await.
            // The Task captures `self` weakly via the closure above.
            Task {
                await self.evaluateAndUpdateShields()
                completionHandler()
            }
        }

        healthStore.execute(query)
        observerQueries.append(query)

        Self.logger.debug("Registered observer query for \(sampleType.identifier)")
    }

    /// Enables background delivery for the given sample type.
    ///
    /// **Why `.hourly`?** This is the most frequent delivery cadence Apple provides.
    /// In practice, if the app is already in memory, the `HKObserverQuery` fires more
    /// frequently (on each HealthKit write). The `.hourly` cadence acts as a floor:
    /// even if the app was terminated, HealthKit will wake it at least once per hour.
    private func enableBackgroundDelivery(for sampleType: HKSampleType) async {
        do {
            try await healthStore.enableBackgroundDelivery(for: sampleType, frequency: .hourly)
            Self.logger.debug("Enabled background delivery for \(sampleType.identifier)")
        } catch {
            Self.logger.error(
                "Failed to enable background delivery for \(sampleType.identifier): \(error.localizedDescription)"
            )
        }
    }

    /// Fetches fresh health data, evaluates the user's goal configuration, and updates
    /// Screen Time shields accordingly.
    ///
    /// **Fail-safe policy:** If any health data fetch fails, shields remain unchanged.
    /// This prevents accidentally unblocking apps when HealthKit is temporarily unavailable
    /// (e.g., system pressure, daemon restart), and also prevents blocking apps that were
    /// already unblocked due to a transient error.
    private func evaluateAndUpdateShields() async {
        // Load today's goal from the weekly schedule.
        // **Why `WeeklyGoalSchedule` instead of `HealthGoal.load()`?** The legacy single-goal
        // key is only synced when `WeeklyGoalSchedule.save()` runs. After midnight, if no
        // user interaction has occurred, the legacy key still holds yesterday's config. Reading
        // from the weekly schedule and deriving today's goal avoids stale evaluations.
        let goal = WeeklyGoalSchedule.load().todayGoal()

        // Bail early if no goals are configured — nothing to evaluate.
        let hasGoals = GoalBlockingEvaluator.hasEnabledGoals(goal: goal)
        guard hasGoals else {
            Self.logger.debug("No enabled goals — skipping background evaluation.")
            return
        }

        do {
            // Fetch current health metrics.
            let currentData = try await healthService.fetchCurrentData()

            // Fetch exercise minutes for each enabled exercise goal.
            var exerciseMinutesByGoalId: [UUID: Int] = [:]
            for exerciseGoal in goal.exerciseGoals where exerciseGoal.isEnabled {
                let minutes = try await healthService.fetchExerciseMinutes(
                    for: exerciseGoal.exerciseType.hkWorkoutActivityType
                )
                exerciseMinutesByGoalId[exerciseGoal.id] = minutes
            }

            // Compute current time for time-block goal evaluation.
            let now = Date()
            let components = Calendar.current.dateComponents([.hour, .minute], from: now)
            let minutesSinceMidnight = (components.hour ?? 0) * 60 + (components.minute ?? 0)

            let snapshot = GoalEvaluationSnapshot(
                steps: currentData.steps,
                activeEnergy: currentData.activeEnergy,
                exerciseMinutesByGoalId: exerciseMinutesByGoalId,
                currentMinutesSinceMidnight: minutesSinceMidnight
            )

            // **Why no MainActor hop?** `GoalBlockingEvaluator` contains pure static
            // functions with no UI or actor-isolated state. Running on the background
            // thread avoids unnecessary main-thread contention during the ~30s budget.
            let shouldBlock = GoalBlockingEvaluator.shouldBlock(goal: goal, snapshot: snapshot)

            try await blockerService.updateShields(shouldBlock: shouldBlock)

            Self.logger.info(
                "Background evaluation complete — shouldBlock: \(shouldBlock), steps: \(currentData.steps), energy: \(currentData.activeEnergy)"
            )
        } catch {
            // Fail-safe: do not change shield state on error.
            Self.logger.error(
                "Background evaluation failed — shields unchanged: \(error.localizedDescription)"
            )
        }
    }
}
