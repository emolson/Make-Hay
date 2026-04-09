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
final class PermissionManager: PermissionManaging {

    // MARK: - State

    /// Current HealthKit authorization status, refreshed on every `refresh()` call.
    var healthAuthorizationStatus: HealthAuthorizationStatus

    /// Whether the one-time HealthKit authorization sheet has already been shown.
    var healthAuthorizationPromptShown: Bool

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

    /// Tracks consecutive `.unconfirmed` probe results while the previous status was
    /// `.authorized`. A single flaky probe (daemon briefly unresponsive after an
    /// app-switch) is tolerated; after the threshold is reached the downgrade is
    /// accepted, which detects a real permission revocation.
    private var consecutiveUnconfirmedCount: Int = 0

    /// Number of consecutive `.unconfirmed` probes required before downgrading a
    /// previously `.authorized` status. Low enough to detect real revocations within
    /// a few foreground resumes, high enough to survive a single flaky daemon response.
    private static let unconfirmedDowngradeThreshold = 2

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

        let seededPromptShown = SharedStorage.healthAuthorizationPromptShown
            || SharedStorage.healthPermissionGranted
        let seededHealthStatus: HealthAuthorizationStatus = SharedStorage.healthPermissionGranted
            ? .authorized
            : .notDetermined

        // Seed from persisted state for a flicker-free first frame.
        self.healthAuthorizationStatus = seededHealthStatus.normalized(promptShown: seededPromptShown)
        self.healthAuthorizationPromptShown = seededPromptShown
        self.screenTimeAuthorized = SharedStorage.screenTimePermissionGranted
    }

    // MARK: - Public Methods

    /// Queries both services for their current authorization state, updates in-memory
    /// properties, and persists the result to `SharedStorage`.
    ///
    /// **Why a dedicated method?** Called on view appear *and* on every foreground resume
    /// so the banner reacts within one frame if the user toggled permissions in Settings.
    func refresh() async {
        async let latestHealthStatus = healthService.authorizationStatus
        async let latestHealthPromptShown = healthService.authorizationPromptShown
        let latestScreenTime = await blockerService.isAuthorized

        let latestPromptShown = await latestHealthPromptShown
        var latestHealth = (await latestHealthStatus).normalized(promptShown: latestPromptShown)

        // Ratchet with revocation detection:
        //
        // Once we've proven readable Health data (.authorized), a single subsequent
        // .unconfirmed probe is tolerated — the HealthKit daemon may be briefly
        // unresponsive after an app-switch (e.g. "Review Health Permissions" → Health
        // app → back). However, if multiple consecutive probes return .unconfirmed,
        // accept the downgrade: the user likely revoked access in the Health app.
        //
        // A full reset (.notDetermined, meaning the prompt must be shown again)
        // always overrides immediately.
        if healthAuthorizationStatus == .authorized && latestHealth == .unconfirmed {
            consecutiveUnconfirmedCount += 1
            if consecutiveUnconfirmedCount < Self.unconfirmedDowngradeThreshold {
                latestHealth = .authorized
            }
            // else: threshold reached — accept the downgrade to .unconfirmed
        } else {
            consecutiveUnconfirmedCount = 0
        }

        healthAuthorizationStatus = latestHealth
        healthAuthorizationPromptShown = latestPromptShown || latestHealth.promptHasBeenShown
        screenTimeAuthorized = latestScreenTime

        // Persist so the next cold-launch seeds the correct initial state.
        SharedStorage.healthPermissionGranted = latestHealth.isAuthorized
        SharedStorage.healthAuthorizationPromptShown = healthAuthorizationPromptShown
        SharedStorage.screenTimePermissionGranted = latestScreenTime
    }

    /// Requests HealthKit authorization, refreshes stored state, and returns the
    /// resulting authorization status.
    ///
    /// **Why return a status?** HealthKit may complete the request call without
    /// presenting UI or granting access. Callers need the post-request status so
    /// they can distinguish a real grant from the "still denied" case and show
    /// the correct manual guidance.
    ///
    /// - Returns: The latest HealthKit authorization status after refresh.
    /// - Throws: Propagates any error from the underlying `HealthServiceProtocol`.
    @discardableResult
    func requestHealthPermission() async throws -> HealthAuthorizationStatus {
        try await healthService.requestAuthorization()
        await refresh()
        return healthAuthorizationStatus
    }

    /// Requests Screen Time (FamilyControls) authorization and refreshes the stored status.
    ///
    /// - Throws: Propagates any error from the underlying `BlockerServiceProtocol`.
    func requestScreenTimePermission() async throws {
        try await blockerService.requestAuthorization()
        await refresh()
    }
}
