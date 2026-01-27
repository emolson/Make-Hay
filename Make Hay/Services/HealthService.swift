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
    
    /// Tracks whether authorization was successfully requested.
    /// **Why track this?** HealthKit doesn't expose a clear "authorized" status for read-only types
    /// due to privacy. We track successful authorization requests ourselves.
    private var hasRequestedAuthorization: Bool = false
    
    // MARK: - Initialization
    
    /// Creates a new HealthService instance.
    /// - Throws: `HealthServiceError.healthKitNotAvailable` if HealthKit is not available on this device.
    init() throws {
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
        
        self.healthStore = HKHealthStore()
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
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: now,
            options: .strictStartDate
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
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
            
            healthStore.execute(query)
        }
    }
    
    /// Fetches the total active energy for the current day.
    /// - Returns: The cumulative active energy (kilocalories) from midnight to now.
    func fetchActiveEnergy() async throws -> Double {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: now,
            options: .strictStartDate
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: activeEnergyType,
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
            
            healthStore.execute(query)
        }
    }
    
    /// Fetches the total exercise minutes for the current day.
    /// If an activity type is provided, totals workout duration for that type.
    /// Otherwise, uses Apple's exercise time quantity.
    func fetchExerciseMinutes(for activityType: HKWorkoutActivityType?) async throws -> Int {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: now,
            options: .strictStartDate
        )
        
        if let activityType {
            let workoutPredicate = HKQuery.predicateForWorkouts(with: activityType)
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, workoutPredicate])
            
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: workoutType,
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
                
                healthStore.execute(query)
            }
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(
                    quantityType: exerciseTimeType,
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
                
                healthStore.execute(query)
            }
        }
    }
}
