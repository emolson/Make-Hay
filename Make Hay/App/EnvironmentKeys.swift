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
/// `GoalStatusProvider`. Injecting a single concrete
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

// MARK: - App Navigation

/// Environment key for shared root-level tab navigation state.
///
/// **Why a concrete type?** Like other `@Observable` environment values in this app,
/// SwiftUI observation needs the concrete instance so tab selection changes invalidate
/// dependent views automatically.
private struct AppNavigationKey: EnvironmentKey {
    @MainActor static let defaultValue: AppNavigationState = AppNavigationState()
}

// MARK: - Background Health Monitor

/// Environment key for the background health monitor.
///
/// **Why expose this?** The Settings screen needs to call `syncNow()` to trigger an
/// immediate foreground sync. Using an environment key keeps the dependency injectable
/// and mock-backed for previews.
private struct BackgroundHealthMonitorKey: EnvironmentKey {
    static let defaultValue: any BackgroundHealthMonitorProtocol = MockBackgroundHealthMonitor()
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

    /// Shared root navigation state for switching tabs from anywhere in the app.
    ///
    /// Inject at the app root: `.environment(\.appNavigation, container.appNavigation)`
    /// Consume in any view: `@Environment(\.appNavigation) private var appNavigation`
    var appNavigation: AppNavigationState {
        get { self[AppNavigationKey.self] }
        set { self[AppNavigationKey.self] = newValue }
    }

    /// The background health monitor for triggering manual syncs.
    ///
    /// Inject at the app root: `.environment(\.backgroundHealthMonitor, container.backgroundHealthMonitor)`
    /// Consume in any view: `@Environment(\.backgroundHealthMonitor) private var backgroundHealthMonitor`
    var backgroundHealthMonitor: any BackgroundHealthMonitorProtocol {
        get { self[BackgroundHealthMonitorKey.self] }
        set { self[BackgroundHealthMonitorKey.self] = newValue }
    }
}
