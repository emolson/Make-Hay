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
    
    // MARK: - Private Properties
    
    private let healthStore: HKHealthStore
    private let stepType: HKQuantityType
    private let activeEnergyType: HKQuantityType
    private let exerciseTimeType: HKQuantityType
    private let workoutType: HKWorkoutType
    
    /// Injected key-value store used for lightweight persistence.
    ///
    /// **Why injected?** `HealthService` only needs a single persisted flag
    /// (`hasRequestedHealthAuthorization`). Coupling directly to `UserDefaults.standard`
    /// makes unit tests hit real disk defaults, introducing flakiness. Injecting a
    /// `KeyValueStorage` protocol lets tests supply an in-memory stub instead.
    private let storage: any KeyValueStorage

    /// Key used to persist the authorization-requested flag.
    private static let authRequestedKey = "hasRequestedHealthAuthorization"

    /// Tracks whether authorization was successfully requested.
    /// **Why persisted?** HealthKit doesn't expose a clear "authorized" status for read-only
    /// types due to privacy. We track successful authorization requests ourselves. This flag
    /// must survive app restarts, otherwise `authorizationStatus` incorrectly reports
    /// `.notDetermined` on every launch (since HealthKit returns `.sharingDenied` for
    /// read-only grants due to privacy).
    private var hasRequestedAuthorization: Bool {
        get { storage.bool(forKey: Self.authRequestedKey) }
        set { storage.set(newValue, forKey: Self.authRequestedKey) }
    }
    
    /// Maximum time to wait for a single HealthKit query before treating it as failed.
    ///
    /// **Why 10 seconds?** HealthKit queries typically return in < 1s. If the HealthKit
    /// daemon is unresponsive (system pressure, post-update), waiting indefinitely traps
    /// the UI in a permanent loading spinner. 10 seconds is generous but bounded.
    private static let queryTimeoutSeconds: UInt64 = 10
    
    // MARK: - Initialization
    
    /// Creates a new HealthService instance.
    /// - Parameters:
    ///   - healthStore: An optional shared `HKHealthStore`. If nil, a new store is created.
    ///   - storage: Key-value store for persisting lightweight flags. Defaults to `UserDefaults.standard`.
    /// - Throws: `HealthServiceError.healthKitNotAvailable` if HealthKit is not available on this device.
    ///
    /// **Why accept an external store?** Apple recommends a single `HKHealthStore` per app.
    /// Sharing the store with `BackgroundHealthMonitor` avoids duplicate connections to the
    /// HealthKit daemon and keeps observer query registration consistent.
    init(healthStore: HKHealthStore? = nil, storage: any KeyValueStorage = UserDefaults.standard) throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthServiceError.healthKitNotAvailable
        }
        
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthServiceError.healthKitNotAvailable
        }
        
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) else {
            throw HealthServiceError.healthKitNotAvailable
        }
        
        self.healthStore = healthStore ?? HKHealthStore()
        self.storage = storage
        self.stepType = stepType
        self.activeEnergyType = activeEnergyType
        self.exerciseTimeType = exerciseTimeType
        self.workoutType = HKObjectType.workoutType()
    }
    
    // MARK: - HealthServiceProtocol
    
    /// Returns the current HealthKit authorization status for step data.
    ///
    /// **Why this approach?** HealthKit doesn't expose a clear "authorized" status for read-only types
    /// due to privacy. We check if we've successfully requested authorization and fall back to
    /// the native status for determining if it's not determined.
    var authorizationStatus: HealthAuthorizationStatus {
        let status = healthStore.authorizationStatus(for: stepType)
        
        switch status {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            // For read-only access, this could mean authorized OR denied (privacy)
            // We use our internal tracking to determine the actual state
            return hasRequestedAuthorization ? .authorized : .notDetermined
        case .sharingAuthorized:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }
    
    /// Requests authorization to read step count data from HealthKit.
    /// - Throws: `HealthServiceError.authorizationDenied` if the user denies access.
    func requestAuthorization() async throws {
        let typesToRead: Set<HKSampleType> = [stepType, activeEnergyType, exerciseTimeType, workoutType]
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            hasRequestedAuthorization = true
        } catch {
            throw HealthServiceError.authorizationDenied
        }
    }
    
    /// Fetches the total step count for the current day using HKStatisticsQuery.
    /// - Returns: The cumulative step count from midnight to now.
    /// - Throws: `HealthServiceError.queryFailed` if the query encounters an error.
    func fetchDailySteps() async throws -> Int {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        let localStepType = stepType
        let localStore = healthStore
        
        return try await withThrowingTimeout(seconds: Self.queryTimeoutSeconds) {
            try await withCheckedThrowingContinuation { continuation in
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
                        continuation.resume(throwing: HealthServiceError.queryFailed(underlying: error))
                        return
                    }
                    
                    let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    continuation.resume(returning: Int(steps))
                }
                
                localStore.execute(query)
            }
        }
    }
    
    /// Fetches the total active energy for the current day.
    /// - Returns: The cumulative active energy (kilocalories) from midnight to now.
    func fetchActiveEnergy() async throws -> Double {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        let localEnergyType = activeEnergyType
        let localStore = healthStore
        
        return try await withThrowingTimeout(seconds: Self.queryTimeoutSeconds) {
            try await withCheckedThrowingContinuation { continuation in
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
                        continuation.resume(throwing: HealthServiceError.queryFailed(underlying: error))
                        return
                    }
                    
                    let calories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    continuation.resume(returning: calories)
                }
                
                localStore.execute(query)
            }
        }
    }
    
    /// Fetches the total exercise minutes for the current day.
    /// If an activity type is provided, totals workout duration for that type.
    /// Otherwise, uses Apple's exercise time quantity.
    func fetchExerciseMinutes(for activityType: HKWorkoutActivityType?) async throws -> Int {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        let localWorkoutType = workoutType
        let localExerciseType = exerciseTimeType
        let localStore = healthStore
        
        if let activityType {
            return try await withThrowingTimeout(seconds: Self.queryTimeoutSeconds) {
                try await withCheckedThrowingContinuation { continuation in
                    let datePredicate = HKQuery.predicateForSamples(
                        withStart: startOfDay,
                        end: now,
                        options: .strictStartDate
                    )
                    let workoutPredicate = HKQuery.predicateForWorkouts(with: activityType)
                    let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, workoutPredicate])
                    let query = HKSampleQuery(
                        sampleType: localWorkoutType,
                        predicate: predicate,
                        limit: HKObjectQueryNoLimit,
                        sortDescriptors: nil
                    ) { _, samples, error in
                        if let error = error {
                            continuation.resume(throwing: HealthServiceError.queryFailed(underlying: error))
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
        } else {
            return try await withThrowingTimeout(seconds: Self.queryTimeoutSeconds) {
                try await withCheckedThrowingContinuation { continuation in
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
                            continuation.resume(throwing: HealthServiceError.queryFailed(underlying: error))
                            return
                        }
                        
                        let minutes = statistics?.sumQuantity()?.doubleValue(for: .minute()) ?? 0
                        continuation.resume(returning: Int(minutes.rounded(.down)))
                    }
                    
                    localStore.execute(query)
                }
            }
        }
    }

    /// Fetches a lightweight aggregate snapshot for current gate evaluation.
    ///
    /// **Why async-let?** Steps and active energy queries are independent, so
    /// fetching concurrently reduces latency before guard decisions.
    func fetchCurrentData() async throws -> HealthCurrentData {
        async let steps = fetchDailySteps()
        async let activeEnergy = fetchActiveEnergy()

        return try await HealthCurrentData(
            steps: steps,
            activeEnergy: activeEnergy
        )
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
}
