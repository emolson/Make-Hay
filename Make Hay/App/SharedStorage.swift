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

    private nonisolated static let logger = AppLogger.logger(category: "SharedStorage")

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

    // MARK: - Evaluation Freshness

    /// Key for the last successful evaluation timestamp (stored as `TimeInterval`).
    private nonisolated static let lastEvaluationTimeKey = "lastEvaluationTime"

    /// Key for the source of the last successful evaluation.
    private nonisolated static let lastEvaluationSourceKey = "lastEvaluationSource"

    /// Key for the last evaluation failure description, if any.
    private nonisolated static let lastEvaluationFailureKey = "lastEvaluationFailure"

    /// Stable failure reasons persisted across processes.
    ///
    /// **Why codes instead of raw strings?** Background monitor failures can include
    /// OS-provided details such as file paths or entitlement diagnostics. Persisting
    /// only coarse reason codes keeps the UI informative without storing sensitive
    /// implementation details in shared App Group defaults.
    enum EvaluationFailureReason: String, Sendable {
        case timeout = "timeout"
        case authorizationUnavailable = "authorizationUnavailable"
        case healthDataUnavailable = "healthDataUnavailable"
        case shieldUpdateFailed = "shieldUpdateFailed"
        case unknown = "unknown"
    }

    /// Sources that can trigger an evaluation cycle. Stored as raw strings in
    /// UserDefaults so both the app and the Device Activity extension can read them
    /// without sharing a compiled enum.
    enum EvaluationSource: String, Sendable {
        case observer = "observer"
        case manualSync = "manualSync"
        case foregroundFallback = "foregroundFallback"
        case extensionUnlock = "extensionUnlock"
    }

    /// How long since the last successful evaluation before the data is considered
    /// stale enough to justify a forced foreground sync.
    ///
    /// **Why 2 hours?** HealthKit background delivery uses `.hourly` cadence, so
    /// under normal conditions the app evaluates at least once per hour. Two hours
    /// accommodates a single missed delivery without over-syncing on every foreground.
    nonisolated static let stalenessThresholdSeconds: TimeInterval = 2 * 60 * 60

    /// Timestamp of the last successful evaluation, or `nil` if no evaluation has
    /// completed yet.
    nonisolated static var lastEvaluationDate: Date? {
        get {
            let interval = appGroupDefaults.double(forKey: lastEvaluationTimeKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                appGroupDefaults.set(date.timeIntervalSince1970, forKey: lastEvaluationTimeKey)
            } else {
                appGroupDefaults.removeObject(forKey: lastEvaluationTimeKey)
            }
        }
    }

    /// The source that produced the most recent successful evaluation.
    nonisolated static var lastEvaluationSource: EvaluationSource? {
        get {
            guard let raw = appGroupDefaults.string(forKey: lastEvaluationSourceKey) else { return nil }
            return EvaluationSource(rawValue: raw)
        }
        set {
            appGroupDefaults.set(newValue?.rawValue, forKey: lastEvaluationSourceKey)
        }
    }

    /// Stable code for the most recent evaluation failure, cleared on success.
    nonisolated static var lastEvaluationFailure: String? {
        get { appGroupDefaults.string(forKey: lastEvaluationFailureKey) }
        set {
            if let value = newValue {
                appGroupDefaults.set(value, forKey: lastEvaluationFailureKey)
            } else {
                appGroupDefaults.removeObject(forKey: lastEvaluationFailureKey)
            }
        }
    }

    /// Whether the last successful evaluation is older than `stalenessThresholdSeconds`.
    nonisolated static var isEvaluationStale: Bool {
        guard let last = lastEvaluationDate else { return true }
        return Date().timeIntervalSince(last) > stalenessThresholdSeconds
    }

    /// Records a successful evaluation with the given source.
    nonisolated static func recordEvaluationSuccess(source: EvaluationSource) {
        lastEvaluationDate = Date()
        lastEvaluationSource = source
        lastEvaluationFailure = nil
    }

    /// Records an evaluation failure reason. Does not update the timestamp.
    nonisolated static func recordEvaluationFailure(_ reason: EvaluationFailureReason) {
        lastEvaluationFailure = reason.rawValue
    }
}
