//
//  HealthServiceProtocol.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation
import HealthKit

/// Lightweight snapshot of current daily health metrics used for gate checks.
struct HealthCurrentData: Sendable {
    let steps: Int
    let activeEnergy: Double
}

/// Protocol defining the interface for HealthKit operations.
/// Conforms to Actor for thread-safe access to health data.
protocol HealthServiceProtocol: Actor {
    /// Returns the current HealthKit authorization status for health data.
    ///
    /// **Why async?** The corrected implementation queries HealthKit's request-status
    /// API and optionally probes for actual data flow, both of which are async.
    /// Callers already `await` this property across actor boundaries.
    var authorizationStatus: HealthAuthorizationStatus { get async }

    /// Whether HealthKit's authorization sheet has already been shown for this read set.
    ///
    /// **Why expose this separately?** Read access cannot always be proven from the
    /// absence of data. Callers use this flag for recovery UI without overloading
    /// `authorizationStatus` with a false denied state.
    var authorizationPromptShown: Bool { get async }
    
    /// Requests authorization to read health data from HealthKit.
    /// - Throws: `HealthServiceError` if authorization fails or HealthKit is unavailable.
    func requestAuthorization() async throws
    
    /// Fetches the total step count for the current day.
    /// - Returns: The number of steps taken today.
    /// - Throws: `HealthServiceError` if the query fails.
    func fetchDailySteps() async throws -> Int
    
    /// Fetches the total active energy burned for the current day.
    /// - Returns: The active energy in kilocalories.
    /// - Throws: `HealthServiceError` if the query fails.
    func fetchActiveEnergy() async throws -> Double
    
    /// Fetches the total exercise minutes for the current day.
    /// - Parameter activityType: Optional workout activity filter. If nil, uses Apple Exercise Time.
    /// - Returns: The number of exercise minutes.
    /// - Throws: `HealthServiceError` if the query fails.
    func fetchExerciseMinutes(for activityType: HKWorkoutActivityType?) async throws -> Int

    /// Fetches a lightweight current snapshot of daily metrics used for gate decisions.
    /// - Returns: Current steps and active energy values.
    /// - Throws: `HealthServiceError` if either query fails.
    func fetchCurrentData() async throws -> HealthCurrentData
}
