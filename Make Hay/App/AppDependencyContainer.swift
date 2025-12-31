//
//  AppDependencyContainer.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation
import Combine

/// Dependency Injection container that instantiates and holds references to all services.
/// Injects protocols, not concrete types, to enable testability and preview support.
@MainActor
final class AppDependencyContainer: ObservableObject, Sendable {
    /// The health service for HealthKit operations.
    let healthService: any HealthServiceProtocol
    
    /// The blocker service for Screen Time/FamilyControls operations.
    let blockerService: any BlockerServiceProtocol
    
    /// Creates a new dependency container with the provided services.
    /// - Parameters:
    ///   - healthService: The service to use for health data. Defaults to real service if available.
    ///   - blockerService: The service to use for app blocking. Defaults to real BlockerService.
    init(
        healthService: (any HealthServiceProtocol)? = nil,
        blockerService: (any BlockerServiceProtocol)? = nil
    ) {
        // Use provided health service, or try to create real one, falling back to mock
        if let healthService = healthService {
            self.healthService = healthService
        } else if let realHealthService = try? HealthService() {
            self.healthService = realHealthService
        } else {
            self.healthService = MockHealthService()
        }
        
        // Use provided blocker service, or create real BlockerService
        if let blockerService = blockerService {
            self.blockerService = blockerService
        } else {
            self.blockerService = BlockerService()
        }
    }
    
    /// Creates a container with mock services configured for previews.
    /// - Parameters:
    ///   - mockSteps: The number of steps the mock health service should return.
    ///   - isBlocking: Whether the mock blocker service should report blocking as active.
    /// - Returns: A configured `AppDependencyContainer` for preview use.
    static func preview(mockSteps: Int = 5_000, isBlocking: Bool = false) -> AppDependencyContainer {
        let mockHealth = MockHealthService()
        let mockBlocker = MockBlockerService()
        
        // Configure mocks asynchronously
        Task {
            await mockHealth.setMockSteps(mockSteps)
            if isBlocking {
                try? await mockBlocker.updateShields(shouldBlock: true)
            }
        }
        
        return AppDependencyContainer(
            healthService: mockHealth,
            blockerService: mockBlocker
        )
    }
}

