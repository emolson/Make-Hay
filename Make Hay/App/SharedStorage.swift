//
//  SharedStorage.swift
//  Make Hay
//
//  Created by GitHub Copilot on 2/19/26.
//

import Foundation

/// Shared storage configuration used by the app and app extensions.
enum SharedStorage {
    /// App Group identifier used for cross-process persistence.
    nonisolated static let appGroupIdentifier: String = "group.ethanolson.Make-Hay"

    /// Shared UserDefaults suite for cross-process state (for example, `HealthGoal`).
    nonisolated static var appGroupDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    /// Shared container root URL for file-based payloads.
    nonisolated static var appGroupContainerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
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
    private static let healthPermissionGrantedKey = "healthPermissionGranted"

    /// Key used to persist whether Screen Time authorization was granted during onboarding.
    private static let screenTimePermissionGrantedKey = "screenTimePermissionGranted"

    /// Whether HealthKit permission was granted during onboarding.
    ///
    /// **Why persist this?** HealthKit doesn't expose a clear "authorized" flag for
    /// read-only types due to privacy. Storing the onboarding result lets the Dashboard
    /// show a correct initial state before the first async permission refresh completes.
    nonisolated static var healthPermissionGranted: Bool {
        get { appGroupDefaults.bool(forKey: healthPermissionGrantedKey) }
        set { appGroupDefaults.set(newValue, forKey: healthPermissionGrantedKey) }
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
