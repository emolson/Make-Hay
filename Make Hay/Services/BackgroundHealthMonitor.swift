//
//  BackgroundHealthMonitor.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/20/26.
//

import BackgroundTasks
import Foundation
import HealthKit
import os.log

/// Actor that registers `HKObserverQuery` instances and enables `enableBackgroundDelivery`
/// for all tracked health types so HealthKit can wake the app in the background when health
/// data changes.
///
/// **Reliability model (defense in depth):**
///
/// 1. **`HKObserverQuery`** — fires on every HealthKit write when the app is in memory.
/// 2. **`enableBackgroundDelivery(.immediate)`** — wakes the app when terminated, best-effort
///    cadence controlled by iOS.
/// 3. **`BGAppRefreshTask`** — orthogonal wake path independent of HealthKit daemon health.
///    Guards against silent observer invalidation after daemon restart.
/// 4. **Foreground sync** — catch-all on every `scenePhase == .active` transition.
///
/// Each layer catches failures from the layer above, ensuring goal evaluation happens
/// even under system pressure, daemon restarts, or throttled delivery.
///
/// **Why Actor?** Observer query callbacks arrive on arbitrary HealthKit background threads.
/// Actor isolation serializes access to the stored query references and prevents data races
/// during concurrent background wakes.
actor BackgroundHealthMonitor: BackgroundHealthMonitorProtocol {

    private nonisolated static let traceCategory = "BackgroundHealthMonitor"

    // MARK: - Dependencies

    private let healthStore: HKHealthStore
    private let healthService: any HealthServiceProtocol
    private let blockerService: any BlockerServiceProtocol

    // MARK: - Private State

    /// Running observer queries keyed by their sample type identifier, stored so they
    /// can be stopped during teardown or replaced during self-healing re-registration.
    private var observerQueries: [String: HKObserverQuery] = [:]

    /// Whether monitoring has been started. Prevents duplicate registration.
    private var isMonitoring: Bool = false

    /// Whether an evaluation is currently in-flight. Used for coalescing.
    private var isEvaluating: Bool = false

    /// Whether another evaluation was requested while one was already running.
    /// When true, a follow-up evaluation runs after the current one completes so the
    /// latest health data is always reflected, without unbounded queue growth.
    private var pendingEvaluation: Bool = false

    /// Maximum time allowed for a complete background evaluation cycle (fetch +
    /// evaluate + shield update). HealthKit gives the app ~30 seconds of background
    /// execution; reserving 5 seconds for observer plumbing and completionHandler
    /// leaves 25 seconds for actual work.
    private static let evaluationBudgetSeconds: UInt64 = 25

    /// Thrown by the budget-timeout task when the evaluation genuinely exceeds
    /// `evaluationBudgetSeconds`. Distinct from `CancellationError` so that
    /// external task cancellation (e.g. a foreground debounce) is not
    /// misreported as a timeout.
    private struct EvaluationBudgetExceeded: Error {}

    /// Logger for background health monitoring events.
    private static let logger = AppLogger.logger(category: "BackgroundHealthMonitor")

    /// The `BGAppRefreshTask` identifier registered with iOS for the secondary
    /// orthogonal wake path that is independent of HealthKit daemon health.
    static let backgroundRefreshTaskIdentifier = "ethanolson.Make-Hay.healthRefresh"

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

    /// Registers observer queries, enables background delivery, and schedules the
    /// `BGAppRefreshTask` for each tracked health type.
    ///
    /// Observer queries and background delivery registrations do **not** persist across app
    /// terminations, so this must be called on every app launch. Calling it multiple times
    /// is safe — duplicate registrations are guarded by `isMonitoring`.
    func startMonitoring() async {
        guard !isMonitoring else {
            Self.logger.debug("Background health monitoring already active — skipping.")
            return
        }

        Self.logger.info("Starting background health monitoring.")

        for sampleType in Self.observedTypes {
            registerObserverQuery(for: sampleType)
            await enableBackgroundDelivery(for: sampleType)
        }

        scheduleBackgroundRefresh()

        isMonitoring = true
        Self.logger.info("Background health monitoring started successfully.")
    }

    /// Stops all observer queries and disables background delivery.
    func stopMonitoring() async {
        Self.logger.info("Stopping background health monitoring.")

        for (_, query) in observerQueries {
            healthStore.stop(query)
        }
        observerQueries.removeAll()

        do {
            try await healthStore.disableAllBackgroundDelivery()
            Self.logger.info("All background deliveries disabled.")
        } catch {
            Self.logger.error("Failed to disable background deliveries.")
        }

        isMonitoring = false
    }

    /// Performs an immediate, foreground-priority sync: fetches latest health data,
    /// evaluates goals, and updates shields.
    ///
    /// Unlike background observer callbacks, this method throws on failure so the
    /// caller (e.g., the Settings refresh button) can surface the error to the user.
    @discardableResult
    func syncNow(reason: String) async throws -> EvaluationResult {
        AppLogger.trace(
            category: Self.traceCategory,
            message: "Manual sync requested. reason=\(reason)"
        )
        let result = try await evaluateAndUpdateShields(throwOnFailure: true, source: .manualSync)
        AppLogger.trace(
            category: Self.traceCategory,
            message: "Manual sync completed successfully. reason=\(reason)"
        )
        return result
    }

    // MARK: - Background App Refresh

    /// Handles a `BGAppRefreshTask` wake.
    ///
    /// **Why this method?** `BGAppRefreshTask` is an orthogonal wake path independent of
    /// HealthKit daemon health. If observer queries were silently invalidated (daemon
    /// restart), this handler re-registers them and runs a fresh evaluation. It also
    /// schedules the next refresh so the chain continues indefinitely.
    ///
    /// - Parameter task: The background task provided by the system.
    func handleBackgroundRefresh(task: BGAppRefreshTask) async {
        Self.logger.info("BGAppRefreshTask fired.")

        // Re-register observer queries idempotently. If the HealthKit daemon restarted
        // and invalidated our queries, this restores them without waiting for the user
        // to open the app.
        reregisterAllObserverQueries()

        // Schedule the next refresh before doing work so the chain is never broken
        // even if evaluation fails or times out.
        scheduleBackgroundRefresh()

        task.expirationHandler = {
            Self.logger.warning("BGAppRefreshTask expiring — evaluation may be incomplete.")
        }

        _ = try? await evaluateAndUpdateShields(throwOnFailure: false, source: .backgroundRefresh)

        task.setTaskCompleted(success: true)
        Self.logger.info("BGAppRefreshTask completed.")
    }

    /// Schedules the next `BGAppRefreshTask`.
    ///
    /// **Why 15 minutes?** This is the minimum `earliestBeginDate` iOS respects. Actual
    /// cadence is system-determined based on app usage frequency, battery, and thermal state.
    /// This provides a safety-net wake independent of HealthKit background delivery.
    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(
            identifier: Self.backgroundRefreshTaskIdentifier
        )
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            Self.logger.debug("Scheduled next BGAppRefreshTask.")
        } catch {
            Self.logger.error("Failed to schedule BGAppRefreshTask.")
        }
    }

    // MARK: - Observer Registration

    /// Registers an `HKObserverQuery` for the given sample type.
    ///
    /// **How this works:** When HealthKit receives new data for this type (e.g., the pedometer
    /// writes new step samples), it invokes the `updateHandler`. If the app is in the background,
    /// HealthKit briefly wakes it (thanks to `enableBackgroundDelivery`), giving us ~30 seconds
    /// to evaluate goals and update shields.
    ///
    /// **Critical:** The `completionHandler` **must** be called when processing is done.
    /// Failing to call it prevents future background deliveries and triggers exponential
    /// backoff on the delivery schedule.
    ///
    /// **Self-healing:** When the `updateHandler` fires with a non-nil error, the query has
    /// been invalidated (e.g., HealthKit daemon restarted). This method detects that condition
    /// and re-registers a fresh query for the same sample type, preventing the app from
    /// becoming permanently "deaf" to HealthKit changes.
    private func registerObserverQuery(for sampleType: HKSampleType) {
        let typeIdentifier = sampleType.identifier

        // Stop any existing query for this type before registering a new one.
        if let existing = observerQueries[typeIdentifier] {
            healthStore.stop(existing)
            observerQueries.removeValue(forKey: typeIdentifier)
        }

        let query = HKObserverQuery(sampleType: sampleType, predicate: nil) {
            [weak self] _, completionHandler, error in

            // --- Self-healing: re-register on observer invalidation ---
            //
            // When the HealthKit daemon restarts (system update, crash, memory pressure),
            // existing observer queries are silently invalidated. The only signal is a
            // non-nil error in the updateHandler. Without re-registration, the app becomes
            // permanently deaf to HealthKit changes until the next cold launch.
            if error != nil {
                Self.logger.error("Observer query invalidated — scheduling re-registration.")
                completionHandler()

                guard let self else { return }
                Task {
                    await self.registerObserverQuery(for: sampleType)
                }
                return
            }

            Self.logger.info("Observer query fired.")

            guard let self else {
                completionHandler()
                return
            }

            // Bridge from the callback-based HKObserverQuery into async/await.
            //
            // **completionHandler timing:** Each observer callback runs exactly one
            // evaluation pass, then calls completionHandler immediately. Coalesced
            // follow-up evaluations run as a separate fire-and-forget Task that is NOT
            // blocking the completionHandler. This prevents late completionHandler calls
            // that trigger exponential backoff on future deliveries.
            Task {
                await self.handleObserverDelivery()
                completionHandler()
            }
        }

        healthStore.execute(query)
        observerQueries[typeIdentifier] = query

        Self.logger.debug("Registered observer query.")
    }

    /// Re-registers all observer queries for tracked types.
    ///
    /// **Why?** Called by `BGAppRefreshTask` handler as a defensive measure. If the
    /// HealthKit daemon restarted between background refresh cycles, this restores
    /// observation without waiting for a user-initiated app launch.
    private func reregisterAllObserverQueries() {
        for sampleType in Self.observedTypes {
            registerObserverQuery(for: sampleType)
        }
        Self.logger.info("Re-registered all observer queries.")
    }

    /// Enables background delivery for the given sample type.
    ///
    /// **Why `.immediate`?** For a goal-unlocking app, perceived latency when the user
    /// meets their goal matters more than marginal battery savings. `.immediate` tells iOS
    /// to wake the app as soon as data arrives (still subject to system budgets). The
    /// previous `.hourly` cadence meant users could wait up to an hour for apps to unlock
    /// after meeting their goal when the app was terminated.
    private func enableBackgroundDelivery(for sampleType: HKSampleType) async {
        do {
            try await healthStore.enableBackgroundDelivery(for: sampleType, frequency: .immediate)
            Self.logger.debug("Enabled background delivery (.immediate).")
        } catch {
            Self.logger.error("Failed to enable background delivery.")
        }
    }

    // MARK: - Observer Callback Handling

    /// Handles a single observer delivery: runs one evaluation pass, then checks whether
    /// a coalesced follow-up is needed.
    ///
    /// **Why separate from `coalescedEvaluate()`?** The previous design called
    /// `completionHandler()` after the full coalesced flow (potentially 2 evaluation passes,
    /// 20-50s total). Apple requires `completionHandler` be called "as soon as processing is
    /// done." Late calls risk process termination and trigger exponential backoff on future
    /// deliveries. This method runs one pass and returns, letting the caller call
    /// `completionHandler` immediately. The follow-up runs independently.
    private func handleObserverDelivery() async {
        if isEvaluating {
            pendingEvaluation = true
            Self.logger.debug("Evaluation already in-flight — coalescing.")
            return
        }

        isEvaluating = true
        _ = try? await evaluateAndUpdateShields(throwOnFailure: false, source: .observer)
        isEvaluating = false

        // Fire-and-forget coalesced follow-up. This runs AFTER the caller's
        // completionHandler has been called, so it does not block the observer contract.
        if pendingEvaluation {
            pendingEvaluation = false
            Self.logger.debug("Scheduling coalesced follow-up evaluation.")
            Task { [weak self] in
                guard let self else { return }
                await self.runCoalescedFollowUp()
            }
        }
    }

    /// Runs a coalesced follow-up evaluation that is NOT tied to any observer
    /// completionHandler.
    ///
    /// **Why a separate method?** Decouples follow-up work from the observer callback
    /// lifecycle. The completionHandler was already called after the first evaluation pass.
    /// This follow-up gets the latest data after multi-sample writes (e.g., workout ending
    /// writes steps, energy, and exercise simultaneously) without blocking or delaying
    /// future background deliveries.
    private func runCoalescedFollowUp() async {
        guard !isEvaluating else {
            pendingEvaluation = true
            return
        }

        isEvaluating = true
        _ = try? await evaluateAndUpdateShields(throwOnFailure: false, source: .observer)
        isEvaluating = false
    }

    // MARK: - Evaluation Pipeline

    /// Fetches fresh health data, evaluates the user's goal configuration, and updates
    /// Screen Time shields accordingly.
    ///
    /// Includes **midnight rollover detection**: if the evaluation day changes between
    /// the start and end of the fetch pipeline (i.e. the evaluation straddles midnight),
    /// the stale result is discarded and the evaluation retries with fresh data for
    /// the new day.
    ///
    /// Includes **permission-revocation safety**: if all fetched health values are zero
    /// and HealthKit authorization is unconfirmed, the evaluator assumes permissions were
    /// revoked and clears shields to avoid permanently trapping the user behind a block.
    ///
    /// - Parameters:
    ///   - throwOnFailure: When `true` (foreground/manual sync), errors propagate
    ///     to the caller. When `false` (background observer), errors are logged and shields
    ///     remain unchanged — the fail-safe policy that prevents accidental unblocking when
    ///     HealthKit is temporarily unavailable.
    ///   - source: The trigger that initiated this evaluation, recorded in shared freshness
    ///     metadata so the app and extension can reason about recency and reliability.
    /// - Returns: The evaluation result containing health metrics and the blocking decision.
    @discardableResult
    private func evaluateAndUpdateShields(
        throwOnFailure: Bool,
        source: SharedStorage.EvaluationSource
    ) async throws -> EvaluationResult {
        // --- Midnight rollover guard ---
        // Detect and handle day changes so stale yesterday data is never applied to today.
        let evaluationDayStart = Calendar.current.startOfDay(for: Date())
        let lastEvalDay = SharedStorage.lastEvaluationDayStart
        let isDayRollover = lastEvalDay != nil && evaluationDayStart != lastEvalDay

        if isDayRollover {
            Self.logger.info("Day rollover detected — resetting evaluation state.")
            // Clear yesterday's snapshot so the dashboard does not display stale data.
            SharedStorage.lastEvaluationSnapshot = nil
            SharedStorage.lastEvaluationDayStart = evaluationDayStart
        } else if lastEvalDay == nil {
            // First-ever evaluation — record the day.
            SharedStorage.lastEvaluationDayStart = evaluationDayStart
        }

        // Load the goal configuration.
        var goal = HealthGoal.load()

        // Disable any one-time goals whose expirationDate has passed.
        if goal.expireGoalsIfNeeded() {
            HealthGoal.save(goal)
        }

        // Bail early if no goals are configured — nothing to evaluate.
        let hasGoals = GoalBlockingEvaluator.hasEnabledGoals(goal: goal)

        do {
            guard hasGoals else {
                Self.logger.debug("No enabled goals — clearing shields and skipping background evaluation.")
                let result = EvaluationResult(
                    steps: 0,
                    activeEnergy: 0,
                    exerciseMinutesByGoalId: [:],
                    shouldBlock: false,
                    timestamp: Date()
                )

                try await blockerService.updateShields(shouldBlock: false)
                SharedStorage.lastEvaluationSnapshot = result
                SharedStorage.recordEvaluationSuccess(source: source)
                return result
            }

            // Wrap the fetch-evaluate-update pipeline in a budget timeout so a
            // hung HealthKit query doesn't consume the entire ~30s wake window
            // without calling the observer completionHandler.
            let result = try await withThrowingTaskGroup(of: EvaluationResult.self) { group in
                group.addTask { [healthService] in
                    // Fetch current health metrics.
                    let currentData = try await healthService.fetchCurrentData()

                    // Fetch exercise minutes for each enabled exercise goal.
                    var exerciseMinutesByGoalId: [UUID: Int] = [:]
                    for exerciseGoal in goal.exerciseGoals where exerciseGoal.isEnabled {
                        try Task.checkCancellation()
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

                    let shouldBlock = GoalBlockingEvaluator.shouldBlock(goal: goal, snapshot: snapshot)

                    return EvaluationResult(
                        steps: currentData.steps,
                        activeEnergy: currentData.activeEnergy,
                        exerciseMinutesByGoalId: exerciseMinutesByGoalId,
                        shouldBlock: shouldBlock,
                        timestamp: now
                    )
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: Self.evaluationBudgetSeconds * 1_000_000_000)
                    throw EvaluationBudgetExceeded()
                }

                guard let result = try await group.next() else {
                    throw CancellationError()
                }
                group.cancelAll()
                return result
            }

            // --- Cross-midnight detection ---
            // If the evaluation started just before midnight and finished just after,
            // the fetched data is for the new day (potentially 0 steps) but the goal state
            // was loaded for the old day. Discard and retry.
            let postEvalDay = Calendar.current.startOfDay(for: Date())
            if postEvalDay != evaluationDayStart {
                Self.logger.info("Evaluation straddled midnight — discarding and retrying.")
                SharedStorage.lastEvaluationDayStart = postEvalDay
                SharedStorage.lastEvaluationSnapshot = nil
                return try await evaluateAndUpdateShields(
                    throwOnFailure: throwOnFailure,
                    source: source
                )
            }

            // --- Permission-revocation safety ---
            // If all fetched values are zero and HealthKit authorization is unconfirmed,
            // assume permissions were revoked. Clear shields to avoid permanently trapping
            // the user behind a block they can never satisfy.
            let allZero = result.steps == 0
                && result.activeEnergy == 0
                && result.exerciseMinutesByGoalId.values.allSatisfy { $0 == 0 }

            if allZero {
                let authStatus = await healthService.authorizationStatus
                if authStatus == .unconfirmed || authStatus == .notDetermined {
                    Self.logger.warning(
                        "Evaluation returned inconclusive health data — clearing shields for safety."
                    )
                    try await blockerService.updateShields(shouldBlock: false)
                    let safeResult = EvaluationResult(
                        steps: 0,
                        activeEnergy: 0,
                        exerciseMinutesByGoalId: [:],
                        shouldBlock: false,
                        timestamp: Date()
                    )
                    SharedStorage.lastEvaluationSnapshot = safeResult
                    SharedStorage.recordEvaluationFailure(.authorizationUnavailable)
                    return safeResult
                }
            }

            try await blockerService.updateShields(shouldBlock: result.shouldBlock)

            // Persist the snapshot and record success in shared freshness metadata.
            SharedStorage.lastEvaluationSnapshot = result
            SharedStorage.lastEvaluationDayStart = evaluationDayStart
            SharedStorage.recordEvaluationSuccess(source: source)

            Self.logger.info("Evaluation completed successfully.")
            return result
        } catch is EvaluationBudgetExceeded {
            Self.logger.error("Background evaluation timed out; shields unchanged.")
            SharedStorage.recordEvaluationFailure(.timeout)
            if throwOnFailure { throw HealthServiceError.queryTimedOut }
            return SharedStorage.lastEvaluationSnapshot ?? EvaluationResult(
                steps: 0, activeEnergy: 0, exerciseMinutesByGoalId: [:],
                shouldBlock: false, timestamp: Date()
            )
        } catch is CancellationError {
            // External cancellation (e.g. foreground debounce replaced the
            // previous task). Not a timeout — propagate silently so the caller
            // can decide what to do.
            Self.logger.debug("Background evaluation cancelled.")
            throw CancellationError()
        } catch {
            let failureReason = failureReason(for: error)
            Self.logger.error("Background evaluation failed; shields unchanged.")
            SharedStorage.recordEvaluationFailure(failureReason)
            if throwOnFailure { throw error }
            return SharedStorage.lastEvaluationSnapshot ?? EvaluationResult(
                steps: 0, activeEnergy: 0, exerciseMinutesByGoalId: [:],
                shouldBlock: false, timestamp: Date()
            )
        }
    }

    // MARK: - Error Classification

    private func failureReason(for error: Error) -> SharedStorage.EvaluationFailureReason {
        switch error {
        case is CancellationError:
            return .timeout
        case HealthServiceError.authorizationDenied,
             BlockerServiceError.authorizationFailed,
             BlockerServiceError.notAuthorized:
            return .authorizationUnavailable
        case HealthServiceError.healthKitNotAvailable,
             HealthServiceError.queryFailed,
             HealthServiceError.queryTimedOut:
            return .healthDataUnavailable
        case BlockerServiceError.configurationUpdateFailed:
            return .shieldUpdateFailed
        default:
            return .unknown
        }
    }
}
