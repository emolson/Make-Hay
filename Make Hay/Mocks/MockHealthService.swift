//
//  MockHealthService.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation
import HealthKit

/// Mock implementation of HealthServiceProtocol for previews and unit tests.
/// Uses an Actor to maintain thread safety while allowing configurable behavior.
actor MockHealthService: HealthServiceProtocol {
    /// The number of steps to return from `fetchDailySteps()`.
    var mockSteps: Int
    /// The active energy to return from `fetchActiveEnergy()`.
    var mockActiveEnergy: Double
    /// The exercise minutes to return from `fetchExerciseMinutes(for:)`.
    var mockExerciseMinutes: Int
    
    /// Mock authorization status.
    var mockAuthorizationStatus: HealthAuthorizationStatus = .authorized

    /// Whether the mock should report the HealthKit sheet as already shown.
    var mockAuthorizationPromptShown: Bool = false

    /// Optional post-request state mutation applied immediately before returning or throwing.
    var mockAuthorizationStatusAfterRequest: HealthAuthorizationStatus?
    var mockAuthorizationPromptShownAfterRequest: Bool?
    
    /// When `true`, all methods will throw their respective errors.
    var shouldThrowError: Bool = false

    /// Creates a mock health service with configurable initial values.
    ///
    /// **Why an init?** Allows previews and tests to configure values synchronously
    /// instead of using fire-and-forget `Task` blocks that race against view rendering.
    init(
        steps: Int = 5_000,
        activeEnergy: Double = 350,
        exerciseMinutes: Int = 20
    ) {
        self.mockSteps = steps
        self.mockActiveEnergy = activeEnergy
        self.mockExerciseMinutes = exerciseMinutes
    }
    
    /// Returns the mock authorization status.
    var authorizationStatus: HealthAuthorizationStatus {
        get async { mockAuthorizationStatus }
    }

    var authorizationPromptShown: Bool {
        get async { mockAuthorizationPromptShown || mockAuthorizationStatus.promptHasBeenShown }
    }
    
    /// Simulates requesting HealthKit authorization.
    /// - Throws: `HealthServiceError.authorizationDenied` if `shouldThrowError` is `true`.
    func requestAuthorization() async throws {
        if let mockAuthorizationStatusAfterRequest {
            mockAuthorizationStatus = mockAuthorizationStatusAfterRequest
        }

        if let mockAuthorizationPromptShownAfterRequest {
            mockAuthorizationPromptShown = mockAuthorizationPromptShownAfterRequest
        }

        if shouldThrowError {
            throw HealthServiceError.authorizationDenied
        }

        mockAuthorizationPromptShown = true
    }
    
    /// Returns the configured `mockSteps` value or throws an error.
    /// - Returns: The mock step count.
    /// - Throws: `HealthServiceError.queryFailed` if `shouldThrowError` is `true`.
    func fetchDailySteps() async throws -> Int {
        if shouldThrowError {
            throw HealthServiceError.queryFailed(
                description: "Mock error for testing"
            )
        }
        return mockSteps
    }
    
    /// Returns the configured `mockActiveEnergy` value or throws an error.
    /// - Returns: The mock active energy in kilocalories.
    /// - Throws: `HealthServiceError.queryFailed` if `shouldThrowError` is `true`.
    func fetchActiveEnergy() async throws -> Double {
        if shouldThrowError {
            throw HealthServiceError.queryFailed(
                description: "Mock error for testing"
            )
        }
        return mockActiveEnergy
    }
    
    /// Returns the configured `mockExerciseMinutes` value or throws an error.
    /// - Parameter activityType: Optional workout filter (ignored by the mock).
    /// - Returns: The mock exercise minutes.
    /// - Throws: `HealthServiceError.queryFailed` if `shouldThrowError` is `true`.
    func fetchExerciseMinutes(for activityType: HKWorkoutActivityType?) async throws -> Int {
        if shouldThrowError {
            throw HealthServiceError.queryFailed(
                description: "Mock error for testing"
            )
        }
        return mockExerciseMinutes
    }

    /// Returns a lightweight aggregate snapshot used by gate checks.
    func fetchCurrentData() async throws -> HealthCurrentData {
        if shouldThrowError {
            throw HealthServiceError.queryFailed(
                description: "Mock error for testing"
            )
        }

        return HealthCurrentData(steps: mockSteps, activeEnergy: mockActiveEnergy)
    }
    
    /// Configures the mock step count. Useful for setting up test scenarios.
    /// - Parameter steps: The number of steps to return.
    func setMockSteps(_ steps: Int) {
        mockSteps = steps
    }
    
    /// Configures the mock active energy.
    /// - Parameter calories: The kilocalories to return.
    func setMockActiveEnergy(_ calories: Double) {
        mockActiveEnergy = calories
    }
    
    /// Configures the mock exercise minutes.
    /// - Parameter minutes: The minutes to return.
    func setMockExerciseMinutes(_ minutes: Int) {
        mockExerciseMinutes = minutes
    }
    
    /// Configures whether the mock should throw errors.
    /// - Parameter shouldThrow: If `true`, methods will throw errors.
    func setShouldThrowError(_ shouldThrow: Bool) {
        shouldThrowError = shouldThrow
    }

    /// Configures the mock authorization status used by `authorizationStatus`.
    /// - Parameter status: The status to report.
    func setMockAuthorizationStatus(_ status: HealthAuthorizationStatus) {
        mockAuthorizationStatus = status
    }

    /// Configures whether the mock should report the HealthKit sheet as already shown.
    /// - Parameter shown: The prompt-shown state to report.
    func setMockAuthorizationPromptShown(_ shown: Bool) {
        mockAuthorizationPromptShown = shown
    }

    /// Configures the authorization state to expose immediately after a request attempt.
    /// - Parameters:
    ///   - status: The status to surface after `requestAuthorization()` is called.
    ///   - promptShown: The prompt-shown state to surface after `requestAuthorization()` is called.
    func setMockAuthorizationOutcomeAfterRequest(
        status: HealthAuthorizationStatus? = nil,
        promptShown: Bool? = nil
    ) {
        mockAuthorizationStatusAfterRequest = status
        mockAuthorizationPromptShownAfterRequest = promptShown
    }
}
