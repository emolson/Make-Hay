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
}
