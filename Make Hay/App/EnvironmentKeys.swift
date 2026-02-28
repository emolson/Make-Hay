//
//  EnvironmentKeys.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/28/26.
//

import SwiftUI

// MARK: - Health Service

/// Environment key for the health service protocol.
///
/// **Why mock default?** Using `MockHealthService()` as the default value means every
/// SwiftUI `#Preview` "just works" without explicit environment injection. Production
/// code always overrides this at the app root, so the mock default is never hit at runtime.
private struct HealthServiceKey: EnvironmentKey {
    static let defaultValue: any HealthServiceProtocol = MockHealthService()
}

// MARK: - Blocker Service

/// Environment key for the blocker service protocol.
///
/// **Why mock default?** Same rationale as `HealthServiceKey` — previews render
/// without boilerplate, and production always injects the real service at the root.
private struct BlockerServiceKey: EnvironmentKey {
    static let defaultValue: any BlockerServiceProtocol = MockBlockerService()
}

// MARK: - Permission Manager

/// Environment key for the shared `PermissionManager`.
///
/// **Why the concrete type?** `@Observable` observation tracking requires access through
/// the concrete type's `ObservationRegistrar`. Protocol existentials break SwiftUI's
/// automatic view invalidation, so we inject the concrete class — same pattern as
/// `DashboardViewModelKey`.
///
/// **Why mock-backed default?** Mock services make previews zero-config — no HealthKit
/// or FamilyControls entitlements needed in the canvas.
private struct PermissionManagerKey: EnvironmentKey {
    @MainActor static let defaultValue: PermissionManager = PermissionManager(
        healthService: MockHealthService(),
        blockerService: MockBlockerService()
    )
}

// MARK: - Dashboard ViewModel

/// Environment key for the shared `DashboardViewModel`.
///
/// **Why the concrete type instead of its protocols?** `DashboardViewModel` conforms to
/// both `GoalStatusProvider` and `ScheduleGoalManaging`. Injecting a single concrete
/// instance avoids needing separate mock classes for each protocol facet. Views that
/// only need one protocol facet simply access it through the VM.
///
/// **Why mock-backed default?** Keeps previews zero-config. The default VM is backed by
/// mock services so it renders meaningful placeholder data without HealthKit or
/// FamilyControls entitlements.
private struct DashboardViewModelKey: EnvironmentKey {
    @MainActor static let defaultValue: DashboardViewModel = DashboardViewModel(
        healthService: MockHealthService(),
        blockerService: MockBlockerService()
    )
}

// MARK: - EnvironmentValues Extension

extension EnvironmentValues {
    /// The health service for HealthKit operations.
    ///
    /// Inject at the app root: `.environment(\.healthService, container.healthService)`
    /// Consume in any view: `@Environment(\.healthService) private var healthService`
    var healthService: any HealthServiceProtocol {
        get { self[HealthServiceKey.self] }
        set { self[HealthServiceKey.self] = newValue }
    }

    /// The blocker service for Screen Time / FamilyControls operations.
    ///
    /// Inject at the app root: `.environment(\.blockerService, container.blockerService)`
    /// Consume in any view: `@Environment(\.blockerService) private var blockerService`
    var blockerService: any BlockerServiceProtocol {
        get { self[BlockerServiceKey.self] }
        set { self[BlockerServiceKey.self] = newValue }
    }

    /// The shared dashboard view model providing goal state, blocking status,
    /// and schedule management across the app.
    ///
    /// Inject at the app root: `.environment(\.dashboardViewModel, container.dashboardViewModel)`
    /// Consume in any view: `@Environment(\.dashboardViewModel) private var dashboardViewModel`
    var dashboardViewModel: DashboardViewModel {
        get { self[DashboardViewModelKey.self] }
        set { self[DashboardViewModelKey.self] = newValue }
    }

    /// The shared permission manager providing HealthKit and Screen Time authorization
    /// state as a single source of truth across all features.
    ///
    /// Inject at the app root: `.environment(\.permissionManager, container.permissionManager)`
    /// Consume in any view: `@Environment(\.permissionManager) private var permissionManager`
    var permissionManager: PermissionManager {
        get { self[PermissionManagerKey.self] }
        set { self[PermissionManagerKey.self] = newValue }
    }
}
