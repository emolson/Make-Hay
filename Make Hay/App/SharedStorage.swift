//
//  SharedStorage.swift
//  Make Hay
//
//  Created by GitHub Copilot on 2/19/26.
//

import Foundation
import os.log

/// Shared storage configuration used by the app and app extensions.
enum SharedStorage {
    /// App Group identifier used for cross-process persistence.
    nonisolated static let appGroupIdentifier: String = "group.ethanolson.Make-Hay"

    private nonisolated static let logger = Logger(
        subsystem: "com.ethanolson.Make-Hay",
        category: "SharedStorage"
    )

    /// Shared UserDefaults suite for cross-process state (for example, `HealthGoal`).
    ///
    /// **Why assert instead of silently falling back?** The app and its extensions
    /// share goal and permission state through App Group UserDefaults. If the suite
    /// cannot be created (misconfigured entitlements, wrong identifier), falling back
    /// to `.standard` silently desyncs the two processes — goals saved by the app
    /// won't be visible to the extension and vice-versa. The assertion catches this
    /// during development; in production the fallback keeps the app running.
    nonisolated static var appGroupDefaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            logger.fault(
                "App Group UserDefaults suite '\(appGroupIdentifier)' unavailable — falling back to .standard. Check entitlements."
            )
            assertionFailure(
                "App Group UserDefaults suite '\(appGroupIdentifier)' is nil. Verify the App Group entitlement is configured for this target."
            )
            return .standard
        }
        return defaults
    }

    /// Shared container root URL for file-based payloads.
    nonisolated static var appGroupContainerURL: URL? {
        let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
        if url == nil {
            logger.fault(
                "App Group container URL for '\(appGroupIdentifier)' is nil. Check entitlements."
            )
            assertionFailure(
                "App Group container URL for '\(appGroupIdentifier)' is nil. Verify the App Group entitlement is configured for this target."
            )
        }
        return url
    }

    nonisolated static var familyActivitySelectionURL: URL? {
        appGroupContainerURL?.appendingPathComponent("FamilyActivitySelection.plist")
    }

    nonisolated static var pendingFamilyActivitySelectionURL: URL? {
        appGroupContainerURL?.appendingPathComponent("PendingFamilyActivitySelection.plist")
    }

    nonisolated static var pendingFamilyActivitySelectionDateURL: URL? {
        appGroupContainerURL?.appendingPathComponent("PendingFamilyActivitySelectionDate.plist")
    }

    // MARK: - Permission Status

    /// Key used to persist whether HealthKit authorization was granted during onboarding.
    private nonisolated static let healthPermissionGrantedKey = "healthPermissionGranted"

    /// Key used to persist whether the HealthKit permission sheet has already been shown.
    private nonisolated static let healthAuthorizationPromptShownKey = "healthAuthorizationPromptShown"

    /// Key used to persist whether Screen Time authorization was granted during onboarding.
    private nonisolated static let screenTimePermissionGrantedKey = "screenTimePermissionGranted"

    /// Whether HealthKit permission was granted during onboarding.
    ///
    /// **Why persist this?** HealthKit doesn't expose a clear "authorized" flag for
    /// read-only types due to privacy. Storing the onboarding result lets the Dashboard
    /// show a correct initial state before the first async permission refresh completes.
    nonisolated static var healthPermissionGranted: Bool {
        get { appGroupDefaults.bool(forKey: healthPermissionGrantedKey) }
        set { appGroupDefaults.set(newValue, forKey: healthPermissionGrantedKey) }
    }

    /// Whether the app has already consumed HealthKit's one-time authorization sheet.
    ///
    /// **Why persist this separately?** Read-only HealthKit permissions cannot always be
    /// distinguished from "no readable samples yet." This flag preserves the recovery UI
    /// path without falsely reporting denied access when the user simply has no recent data.
    nonisolated static var healthAuthorizationPromptShown: Bool {
        get { appGroupDefaults.bool(forKey: healthAuthorizationPromptShownKey) }
        set { appGroupDefaults.set(newValue, forKey: healthAuthorizationPromptShownKey) }
    }

    /// Whether Screen Time permission was granted during onboarding.
    ///
    /// **Why persist this?** Same rationale — the DashboardViewModel seeds its
    /// `screenTimePermissionGranted` property from this value on init, avoiding a
    /// brief flash of the permissions banner before the live check completes.
    nonisolated static var screenTimePermissionGranted: Bool {
        get { appGroupDefaults.bool(forKey: screenTimePermissionGrantedKey) }
        set { appGroupDefaults.set(newValue, forKey: screenTimePermissionGrantedKey) }
    }
}
