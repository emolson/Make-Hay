//
//  PermissionManager.swift
//  Make Hay
//
//  Created by GitHub Copilot on 2/28/26.
//

import Foundation

/// Centralised permission state manager for HealthKit and Screen Time authorizations.
///
/// **Why a dedicated manager?** Permission status was previously duplicated across
/// `DashboardViewModel`, `SettingsView`, and `OnboardingViewModel` — each owning its
/// own copy of the query + SharedStorage-sync logic. `PermissionManager` becomes the
/// single source of truth: it seeds from `SharedStorage` on init (for instant cold-launch
/// rendering), queries the live services on `refresh()`, and writes the result back to
/// `SharedStorage` so the next cold launch is accurate.
///
/// **Why `@Observable`?** Views that read `isPermissionMissing` or the individual
/// statuses get automatic SwiftUI invalidation when the values change, with no Combine
/// or manual objectWillChange plumbing.
///
/// **Why `@MainActor`?** All properties drive UI state; isolating to the main actor
/// prevents data-race warnings under Strict Concurrency and guarantees SwiftUI reads
/// are always on the main thread.
@Observable
@MainActor
final class PermissionManager {

    // MARK: - State

    /// Current HealthKit authorization status, refreshed on every `refresh()` call.
    var healthAuthorizationStatus: HealthAuthorizationStatus

    /// Current Screen Time (FamilyControls) authorization status.
    var screenTimeAuthorized: Bool

    /// Whether any required permission is currently missing.
    ///
    /// **Why computed?** Single derived value consumed by views to decide whether to
    /// show the permissions banner. Never drifts from the two underlying statuses.
    var isPermissionMissing: Bool {
        healthAuthorizationStatus != .authorized || !screenTimeAuthorized
    }

    // MARK: - Dependencies

    private let healthService: any HealthServiceProtocol
    private let blockerService: any BlockerServiceProtocol

    // MARK: - Initialization

    /// Creates a new PermissionManager backed by the given services.
    ///
    /// **Why seed from SharedStorage?** The first `refresh()` is async. Seeding from
    /// persisted state lets views render the correct banner/icon on the very first
    /// frame — no flash of "everything is fine" if the user revoked permissions while
    /// the app was terminated.
    ///
    /// - Parameters:
    ///   - healthService: Service used to query and request HealthKit authorization.
    ///   - blockerService: Service used to query and request Screen Time authorization.
    init(
        healthService: any HealthServiceProtocol,
        blockerService: any BlockerServiceProtocol
    ) {
        self.healthService = healthService
        self.blockerService = blockerService

        // Seed from persisted state for a flicker-free first frame.
        self.healthAuthorizationStatus = SharedStorage.healthPermissionGranted
            ? .authorized
            : .notDetermined
        self.screenTimeAuthorized = SharedStorage.screenTimePermissionGranted
    }

    // MARK: - Public Methods

    /// Queries both services for their current authorization state, updates in-memory
    /// properties, and persists the result to `SharedStorage`.
    ///
    /// **Why a dedicated method?** Called on view appear *and* on every foreground resume
    /// so the banner reacts within one frame if the user toggled permissions in Settings.
    func refresh() async {
        let latestHealth = await healthService.authorizationStatus
        let latestScreenTime = await blockerService.isAuthorized

        healthAuthorizationStatus = latestHealth
        screenTimeAuthorized = latestScreenTime

        // Persist so the next cold-launch seeds the correct initial state.
        SharedStorage.healthPermissionGranted = (latestHealth == .authorized)
        SharedStorage.screenTimePermissionGranted = latestScreenTime
    }

    /// Requests HealthKit authorization and refreshes the stored status.
    ///
    /// - Throws: Propagates any error from the underlying `HealthServiceProtocol`.
    func requestHealthPermission() async throws {
        try await healthService.requestAuthorization()
        await refresh()
    }

    /// Requests Screen Time (FamilyControls) authorization and refreshes the stored status.
    ///
    /// - Throws: Propagates any error from the underlying `BlockerServiceProtocol`.
    func requestScreenTimePermission() async throws {
        try await blockerService.requestAuthorization()
        await refresh()
    }
}
