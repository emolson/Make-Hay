//
//  HealthServiceProtocol.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation

/// Protocol defining the interface for HealthKit operations.
/// Conforms to Actor for thread-safe access to health data.
protocol HealthServiceProtocol: Actor {
    /// Returns the current HealthKit authorization status for step data.
    /// Note: HealthKit only returns `.notDetermined` or `.sharingDenied` for privacy.
    /// A successful query after authorization indicates the user approved access.
    var authorizationStatus: HealthAuthorizationStatus { get }
    
    /// Requests authorization to read health data from HealthKit.
    /// - Throws: `HealthServiceError` if authorization fails or HealthKit is unavailable.
    func requestAuthorization() async throws
    
    /// Fetches the total step count for the current day.
    /// - Returns: The number of steps taken today.
    /// - Throws: `HealthServiceError` if the query fails.
    func fetchDailySteps() async throws -> Int
}
