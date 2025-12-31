//
//  MockHealthService.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation

/// Mock implementation of HealthServiceProtocol for previews and unit tests.
/// Uses an Actor to maintain thread safety while allowing configurable behavior.
actor MockHealthService: HealthServiceProtocol {
    /// The number of steps to return from `fetchDailySteps()`.
    var mockSteps: Int = 5_000
    
    /// When `true`, all methods will throw their respective errors.
    var shouldThrowError: Bool = false
    
    /// Simulates requesting HealthKit authorization.
    /// - Throws: `HealthServiceError.authorizationDenied` if `shouldThrowError` is `true`.
    func requestAuthorization() async throws {
        if shouldThrowError {
            throw HealthServiceError.authorizationDenied
        }
    }
    
    /// Returns the configured `mockSteps` value or throws an error.
    /// - Returns: The mock step count.
    /// - Throws: `HealthServiceError.queryFailed` if `shouldThrowError` is `true`.
    func fetchDailySteps() async throws -> Int {
        if shouldThrowError {
            throw HealthServiceError.queryFailed(
                underlying: NSError(
                    domain: "MockHealthService",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Mock error for testing"]
                )
            )
        }
        return mockSteps
    }
    
    /// Configures the mock step count. Useful for setting up test scenarios.
    /// - Parameter steps: The number of steps to return.
    func setMockSteps(_ steps: Int) {
        mockSteps = steps
    }
    
    /// Configures whether the mock should throw errors.
    /// - Parameter shouldThrow: If `true`, methods will throw errors.
    func setShouldThrowError(_ shouldThrow: Bool) {
        shouldThrowError = shouldThrow
    }
}
