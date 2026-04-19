//
//  HealthService.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation
import HealthKit

/// Actor responsible for all HealthKit interactions.
/// Uses strict concurrency to ensure thread-safe access to health data.
///
/// **Why Actor?** HealthKit queries run on background threads, and we need to ensure
/// thread-safe access to the HKHealthStore. An actor provides this isolation automatically.
actor HealthService: HealthServiceProtocol {

    private nonisolated static let traceCategory = "HealthService"

    // MARK: - Private Properties

    private let healthStore: HKHealthStore
    private let stepType: HKQuantityType
    private let activeEnergyType: HKQuantityType
    private let exerciseTimeType: HKQuantityType
    private let workoutType: HKWorkoutType

    /// The full set of types the app requests read access for.
    /// Computed once and cached so `authorizationStatus` and `requestAuthorization`
    /// always agree on the exact type set.
    private var typesToRead: Set<HKObjectType> {
        [stepType, activeEnergyType, exerciseTimeType, workoutType]
    }

    /// Maximum time to wait for a single HealthKit query before treating it as failed.
    ///
    /// **Why 10 seconds?** HealthKit queries typically return in < 1s. If the HealthKit
    /// daemon is unresponsive (system pressure, post-update), waiting indefinitely traps
    /// the UI in a permanent loading spinner. 10 seconds is generous but bounded.
    private static let queryTimeoutSeconds: UInt64 = 10

    /// Simulator HealthKit frequently consumes the authorization sheet without exposing
    /// any readable samples we can probe. Treating `.unnecessary` as connected there
    /// prevents onboarding from getting stuck behind an impossible verification step.
    private nonisolated static var assumesAuthorizationOncePromptConsumed: Bool {
        #if targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }

    // MARK: - Initialization

    /// Creates a new HealthService instance.
    /// - Parameters:
    ///   - healthStore: An optional shared `HKHealthStore`. If nil, a new store is created.
    /// - Throws: `HealthServiceError.healthKitNotAvailable` if HealthKit is not available on this device.
    ///
    /// **Why accept an external store?** Apple recommends a single `HKHealthStore` per app.
    /// Sharing the store with `BackgroundHealthMonitor` avoids duplicate connections to the
    /// HealthKit daemon and keeps observer query registration consistent.
    init(healthStore: HKHealthStore? = nil) throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthServiceError.healthKitNotAvailable
        }

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthServiceError.healthKitNotAvailable
        }

        guard
            let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)
        else {
            throw HealthServiceError.healthKitNotAvailable
        }

        self.healthStore = healthStore ?? HKHealthStore()
        self.stepType = stepType
        self.activeEnergyType = activeEnergyType
        self.exerciseTimeType = exerciseTimeType
        self.workoutType = HKObjectType.workoutType()
    }

    // MARK: - HealthServiceProtocol

    /// Returns the current HealthKit authorization status for health data.
    ///
    /// **Why `statusForAuthorizationRequest`?** Apple's `authorizationStatus(for:)` only
    /// reflects *write* permission. For read-only types it always returns `.sharingDenied`
    /// regardless of whether the user granted read access — Apple intentionally hides read
    /// grants for privacy. The request-status API tells us whether the permission sheet
    /// would still appear (`.shouldRequest`) or has already been presented (`.unnecessary`).
    ///
    /// **Post-prompt verification:** Once the sheet has been shown, we do a lightweight
    /// probe across the requested sample types to detect whether readable data is
    /// actually flowing. A successful read proves `.authorized`; no readable samples is
    /// treated as inconclusive and remains `.unconfirmed` rather than a false denial.
    var authorizationStatus: HealthAuthorizationStatus {
        get async {
            AppLogger.trace(
                category: Self.traceCategory,
                message: "authorizationStatus query started."
            )
            do {
                let requestStatus = try await authorizationRequestStatus()
                let resolvedStatus: HealthAuthorizationStatus
                switch requestStatus {
                case .shouldRequest:
                    // The user has never been prompted for these types.
                    resolvedStatus = .notDetermined
                case .unnecessary:
                    // The prompt has already been shown. Probe for proven readable data
                    // because HealthKit hides whether read-only permission was granted.
                    let hasAccess = await probeHealthDataAccess()
                    resolvedStatus =
                        hasAccess || Self.assumesAuthorizationOncePromptConsumed
                        ? .authorized
                        : .unconfirmed
                case .unknown:
                    resolvedStatus = .notDetermined
                @unknown default:
                    resolvedStatus = .notDetermined
                }

                AppLogger.trace(
                    category: Self.traceCategory,
                    message: "authorizationStatus query completed."
                )
                return resolvedStatus
            } catch {
                AppLogger.trace(
                    category: Self.traceCategory,
                    message: "authorizationStatus query failed; using fallback."
                )
                return .notDetermined
            }
        }
    }

    var authorizationPromptShown: Bool {
        get async {
            AppLogger.trace(
                category: Self.traceCategory,
                message: "authorizationPromptShown query started."
            )
            do {
                let requestStatus = try await authorizationRequestStatus()
                let promptShown: Bool
                switch requestStatus {
                case .unnecessary:
                    promptShown = true
                case .shouldRequest, .unknown:
                    promptShown = false
                @unknown default:
                    promptShown = false
                }

                AppLogger.trace(
                    category: Self.traceCategory,
                    message: "authorizationPromptShown query completed."
                )
                return promptShown
            } catch {
                AppLogger.trace(
                    category: Self.traceCategory,
                    message: "authorizationPromptShown query failed; using fallback."
                )
                return false
            }
        }
    }

    /// Requests authorization to read health data from HealthKit.
    /// - Throws: `HealthServiceError.authorizationDenied` if the request fails.
    ///
    /// **Why no local flag?** The previous implementation set a persisted
    /// `hasRequestedAuthorization` flag here and used it as a proxy for read access.
    /// That was incorrect — Apple's docs explicitly state the success return value
    /// only indicates the request completed, not that the user granted permission.
    /// The corrected `authorizationStatus` now queries HealthKit directly instead.
    func requestAuthorization() async throws {
        AppLogger.trace(
            category: Self.traceCategory,
            message: "requestAuthorization started."
        )
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            AppLogger.trace(
                category: Self.traceCategory,
                message: "requestAuthorization completed successfully."
            )
        } catch {
            AppLogger.trace(
                category: Self.traceCategory,
                message: "requestAuthorization failed."
            )
            throw HealthServiceError.authorizationDenied
        }
    }

    // MARK: - Private Helpers

    /// Attempts lightweight reads across the requested HealthKit types.
    ///
    /// **Why a probe?** After the permission sheet is dismissed, HealthKit's request-status
    /// API only tells us the prompt was shown, not whether the user toggled any types on.
    /// A non-zero quantity or existing workout proves read access; the absence of readable
    /// samples remains ambiguous, so we do not map it to denied.
    ///
    /// **Why 7 days?** Using only today's data would produce false negatives every morning
    /// before the user starts moving. A 7-day window reduces that, while still keeping the
    /// query bounded and fast.
    private func probeHealthDataAccess() async -> Bool {
        AppLogger.trace(
            category: Self.traceCategory,
            message: "probeHealthDataAccess started."
        )
        let now = Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        async let stepsReadable = recentQuantityDataExists(
            for: stepType,
            unit: .count(),
            start: sevenDaysAgo,
            end: now
        )
        async let activeEnergyReadable = recentQuantityDataExists(
            for: activeEnergyType,
            unit: .kilocalorie(),
            start: sevenDaysAgo,
            end: now
        )
        async let exerciseReadable = recentQuantityDataExists(
            for: exerciseTimeType,
            unit: .minute(),
            start: sevenDaysAgo,
            end: now
        )
        async let workoutReadable = recentWorkoutDataExists(
            start: sevenDaysAgo,
            end: now
        )

        let readabilityChecks = await [
            stepsReadable,
            activeEnergyReadable,
            exerciseReadable,
            workoutReadable,
        ]

        let hasReadableData = readabilityChecks.contains(true)
        AppLogger.trace(
            category: Self.traceCategory,
            message: "probeHealthDataAccess completed."
        )
        return hasReadableData
    }

    // MARK: - Data Fetching

    /// Fetches the total step count for the current day using HKStatisticsQuery.
    /// - Returns: The cumulative step count from midnight to now.
    /// - Throws: `HealthServiceError.queryFailed` if the query encounters an error.
    func fetchDailySteps() async throws -> Int {
        AppLogger.trace(
            category: Self.traceCategory,
            message: "fetchDailySteps started."
        )
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        let localStepType = stepType
        let localStore = healthStore

        let steps = try await withThrowingTimeout(seconds: Self.queryTimeoutSeconds) {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Int, Error>) in
                let predicate = HKQuery.predicateForSamples(
                    withStart: startOfDay,
                    end: now,
                    options: .strictStartDate
                )
                let query = HKStatisticsQuery(
                    quantityType: localStepType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    if let error = error {
                        if HealthServiceError.isNoDataError(error) {
                            continuation.resume(returning: 0)
                            return
                        }

                        continuation.resume(
                            throwing: HealthServiceError.queryFailed(
                                description: error.localizedDescription))
                        return
                    }

                    let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    continuation.resume(returning: Int(steps))
                }

                localStore.execute(query)
            }
        }
        AppLogger.trace(
            category: Self.traceCategory,
            message: "fetchDailySteps completed."
        )
        return steps
    }

    /// Fetches the total active energy for the current day.
    /// - Returns: The cumulative active energy (kilocalories) from midnight to now.
    func fetchActiveEnergy() async throws -> Double {
        AppLogger.trace(
            category: Self.traceCategory,
            message: "fetchActiveEnergy started."
        )
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        let localEnergyType = activeEnergyType
        let localStore = healthStore

        let activeEnergy = try await withThrowingTimeout(seconds: Self.queryTimeoutSeconds) {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Double, Error>) in
                let predicate = HKQuery.predicateForSamples(
                    withStart: startOfDay,
                    end: now,
                    options: .strictStartDate
                )
                let query = HKStatisticsQuery(
                    quantityType: localEnergyType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    if let error = error {
                        if HealthServiceError.isNoDataError(error) {
                            continuation.resume(returning: 0)
                            return
                        }

                        continuation.resume(
                            throwing: HealthServiceError.queryFailed(
                                description: error.localizedDescription))
                        return
                    }

                    let calories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    continuation.resume(returning: calories)
                }

                localStore.execute(query)
            }
        }
        AppLogger.trace(
            category: Self.traceCategory,
            message: "fetchActiveEnergy completed."
        )
        return activeEnergy
    }

    /// Fetches the total exercise minutes for the current day.
    /// If an activity type is provided, totals workout duration for that type.
    /// Otherwise, uses Apple's exercise time quantity.
    func fetchExerciseMinutes(for activityType: HKWorkoutActivityType?) async throws -> Int {
        AppLogger.trace(
            category: Self.traceCategory,
            message: "fetchExerciseMinutes started."
        )
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        let localWorkoutType = workoutType
        let localExerciseType = exerciseTimeType
        let localStore = healthStore

        if let activityType {
            let minutes = try await withThrowingTimeout(seconds: Self.queryTimeoutSeconds) {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Int, Error>) in
                    let datePredicate = HKQuery.predicateForSamples(
                        withStart: startOfDay,
                        end: now,
                        options: .strictStartDate
                    )
                    let workoutPredicate = HKQuery.predicateForWorkouts(with: activityType)
                    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                        datePredicate, workoutPredicate,
                    ])
                    let query = HKSampleQuery(
                        sampleType: localWorkoutType,
                        predicate: predicate,
                        limit: HKObjectQueryNoLimit,
                        sortDescriptors: nil
                    ) { _, samples, error in
                        if let error = error {
                            if HealthServiceError.isNoDataError(error) {
                                continuation.resume(returning: 0)
                                return
                            }

                            continuation.resume(
                                throwing: HealthServiceError.queryFailed(
                                    description: error.localizedDescription))
                            return
                        }

                        let totalSeconds = (samples ?? [])
                            .compactMap { $0 as? HKWorkout }
                            .reduce(0.0) { $0 + $1.duration }
                        let minutes = Int((totalSeconds / 60.0).rounded(.down))
                        continuation.resume(returning: minutes)
                    }

                    localStore.execute(query)
                }
            }
            AppLogger.trace(
                category: Self.traceCategory,
                message: "fetchExerciseMinutes completed."
            )
            return minutes
        } else {
            let minutes = try await withThrowingTimeout(seconds: Self.queryTimeoutSeconds) {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Int, Error>) in
                    let datePredicate = HKQuery.predicateForSamples(
                        withStart: startOfDay,
                        end: now,
                        options: .strictStartDate
                    )
                    let query = HKStatisticsQuery(
                        quantityType: localExerciseType,
                        quantitySamplePredicate: datePredicate,
                        options: .cumulativeSum
                    ) { _, statistics, error in
                        if let error = error {
                            if HealthServiceError.isNoDataError(error) {
                                continuation.resume(returning: 0)
                                return
                            }

                            continuation.resume(
                                throwing: HealthServiceError.queryFailed(
                                    description: error.localizedDescription))
                            return
                        }

                        let minutes = statistics?.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                        continuation.resume(returning: Int(minutes.rounded(.down)))
                    }

                    localStore.execute(query)
                }
            }
            AppLogger.trace(
                category: Self.traceCategory,
                message: "fetchExerciseMinutes completed."
            )
            return minutes
        }
    }

    /// Fetches a lightweight aggregate snapshot for current gate evaluation.
    ///
    /// **Why async-let?** Steps and active energy queries are independent, so
    /// fetching concurrently reduces latency before guard decisions.
    func fetchCurrentData() async throws -> HealthCurrentData {
        AppLogger.trace(
            category: Self.traceCategory,
            message: "fetchCurrentData started."
        )
        async let steps = fetchDailySteps()
        async let activeEnergy = fetchActiveEnergy()

        let snapshot = try await HealthCurrentData(
            steps: steps,
            activeEnergy: activeEnergy
        )
        AppLogger.trace(
            category: Self.traceCategory,
            message: "fetchCurrentData completed."
        )
        return snapshot
    }

    // MARK: - Private Helpers

    /// Races an async operation against a deadline.
    ///
    /// **Why?** `withCheckedThrowingContinuation` wrapping HealthKit callbacks will
    /// hang forever if the callback is never invoked (daemon crash, system pressure).
    /// This helper ensures we always resume within a bounded time, surfacing a clear
    /// timeout error instead of an infinite loading spinner.
    private func withThrowingTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw HealthServiceError.queryTimedOut
            }

            // The first task to finish wins; cancel the loser.
            guard let result = try await group.next() else {
                throw HealthServiceError.queryTimedOut
            }
            group.cancelAll()
            return result
        }
    }

    private func authorizationRequestStatus() async throws -> HKAuthorizationRequestStatus {
        AppLogger.trace(
            category: Self.traceCategory,
            message: "authorizationRequestStatus started."
        )
        return try await healthStore.statusForAuthorizationRequest(
            toShare: [],
            read: typesToRead
        )
    }

    private func recentQuantityDataExists(
        for quantityType: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async -> Bool {
        let localStore = healthStore

        do {
            let total = try await withThrowingTimeout(seconds: Self.queryTimeoutSeconds) {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Double, Error>) in
                    let predicate = HKQuery.predicateForSamples(
                        withStart: start,
                        end: end,
                        options: .strictStartDate
                    )
                    let query = HKStatisticsQuery(
                        quantityType: quantityType,
                        quantitySamplePredicate: predicate,
                        options: .cumulativeSum
                    ) { _, statistics, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }

                        let sum = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                        continuation.resume(returning: sum)
                    }

                    localStore.execute(query)
                }
            }

            return total > 0
        } catch {
            return false
        }
    }

    private func recentWorkoutDataExists(start: Date, end: Date) async -> Bool {
        let localWorkoutType = workoutType
        let localStore = healthStore

        do {
            return try await withThrowingTimeout(seconds: Self.queryTimeoutSeconds) {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Bool, Error>) in
                    let predicate = HKQuery.predicateForSamples(
                        withStart: start,
                        end: end,
                        options: .strictStartDate
                    )
                    let query = HKSampleQuery(
                        sampleType: localWorkoutType,
                        predicate: predicate,
                        limit: 1,
                        sortDescriptors: nil
                    ) { _, samples, error in
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }

                        continuation.resume(returning: (samples?.isEmpty == false))
                    }

                    localStore.execute(query)
                }
            }
        } catch {
            return false
        }
    }
}
