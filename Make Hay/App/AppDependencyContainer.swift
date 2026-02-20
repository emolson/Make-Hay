//
//  AppDependencyContainer.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation
import Combine
import HealthKit

/// Dependency Injection container that instantiates and holds references to all services.
/// Injects protocols, not concrete types, to enable testability and preview support.
@MainActor
final class AppDependencyContainer: ObservableObject {
    /// The health service for HealthKit operations.
    let healthService: any HealthServiceProtocol
    
    /// The blocker service for Screen Time/FamilyControls operations.
    let blockerService: any BlockerServiceProtocol

    /// Background health monitor that observes HealthKit changes and evaluates goals.
    ///
    /// **Why here?** The container owns the lifecycle of all services. Starting monitoring
    /// on init ensures observer queries are registered on every app launch, which is
    /// required since `enableBackgroundDelivery` registrations don't persist across
    /// app terminations.
    let backgroundHealthMonitor: any BackgroundHealthMonitorProtocol

    /// Shared dashboard view model used across tabs for consistent gate state.
    lazy var dashboardViewModel: DashboardViewModel = DashboardViewModel(
        healthService: healthService,
        blockerService: blockerService
    )
    
    /// Creates a new dependency container with the provided services.
    /// - Parameters:
    ///   - healthService: The service to use for health data. Defaults to real service if available.
    ///   - blockerService: The service to use for app blocking. Defaults to real BlockerService.
    ///   - backgroundHealthMonitor: The background monitor. Defaults to real monitor if HealthKit is available.
    init(
        healthService: (any HealthServiceProtocol)? = nil,
        blockerService: (any BlockerServiceProtocol)? = nil,
        backgroundHealthMonitor: (any BackgroundHealthMonitorProtocol)? = nil
    ) {
        // Create a shared HKHealthStore for use across services.
        // **Why shared?** Apple recommends a single store per app to avoid duplicate
        // connections to the HealthKit daemon.
        let sharedStore: HKHealthStore? = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil

        // Use provided health service, or try to create real one.
        let resolvedHealthService: any HealthServiceProtocol
        if let healthService = healthService {
            resolvedHealthService = healthService
        } else if let sharedStore, let realHealthService = try? HealthService(healthStore: sharedStore) {
            resolvedHealthService = realHealthService
        } else {
            resolvedHealthService = MockHealthService()
        }
        self.healthService = resolvedHealthService
        
        // Use provided blocker service, or create real BlockerService, falling back to mock
        let resolvedBlockerService: any BlockerServiceProtocol
        if let blockerService = blockerService {
            resolvedBlockerService = blockerService
        } else {
            // BlockerService init doesn't throw, but we still provide a mock fallback
            // for consistency and to support environments where FamilyControls may be unavailable
            resolvedBlockerService = BlockerService()
        }
        self.blockerService = resolvedBlockerService

        // Use provided background monitor, or create real one if HealthKit is available.
        if let backgroundHealthMonitor = backgroundHealthMonitor {
            self.backgroundHealthMonitor = backgroundHealthMonitor
        } else if let sharedStore {
            self.backgroundHealthMonitor = BackgroundHealthMonitor(
                healthStore: sharedStore,
                healthService: resolvedHealthService,
                blockerService: resolvedBlockerService
            )
        } else {
            self.backgroundHealthMonitor = MockBackgroundHealthMonitor()
        }

        // Start background health monitoring immediately.
        // **Why here?** Observer queries and `enableBackgroundDelivery` registrations
        // don't persist across app terminations. They must be re-registered on every
        // launch. Starting in init ensures this happens as early as possible.
        let monitor = self.backgroundHealthMonitor
        Task {
            await monitor.startMonitoring()
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
        let mockMonitor = MockBackgroundHealthMonitor()
        
        // Configure mocks asynchronously
        Task {
            await mockHealth.setMockSteps(mockSteps)
            if isBlocking {
                try? await mockBlocker.updateShields(shouldBlock: true)
            }
        }
        
        return AppDependencyContainer(
            healthService: mockHealth,
            blockerService: mockBlocker,
            backgroundHealthMonitor: mockMonitor
        )
    }
}

