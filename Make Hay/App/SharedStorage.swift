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
        case backgroundRefresh = "backgroundRefresh"
    }

    /// How long since the last successful evaluation before the data is considered
    /// stale enough to justify a forced foreground sync.
    ///
    /// **Why 30 minutes?** HealthKit background delivery now uses `.immediate` cadence,
    /// and `BGAppRefreshTask` provides an orthogonal wake every ~15 min. Under normal
    /// conditions, evaluations happen within minutes of a HealthKit write. 30 minutes
    /// accommodates system throttling under pressure without over-syncing.
    nonisolated static let stalenessThresholdSeconds: TimeInterval = 30 * 60

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

    // MARK: - Day Tracking

    /// Key for the start-of-day `Date` of the most recent evaluation.
    private nonisolated static let lastEvaluationDayStartKey = "lastEvaluationDayStart"

    /// The start-of-day `Date` for the most recent successful evaluation.
    ///
    /// **Why track this?** Midnight rollover detection: when the current day differs
    /// from the stored day, yesterday's snapshot is stale and the evaluator re-engages
    /// blocking so the user must re-earn their unlock for the new day.
    nonisolated static var lastEvaluationDayStart: Date? {
        get {
            let interval = appGroupDefaults.double(forKey: lastEvaluationDayStartKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                appGroupDefaults.set(date.timeIntervalSince1970, forKey: lastEvaluationDayStartKey)
            } else {
                appGroupDefaults.removeObject(forKey: lastEvaluationDayStartKey)
            }
        }
    }

    // MARK: - Evaluation Snapshot

    /// Key for the JSON-encoded `EvaluationResult` written after each successful evaluation.
    private nonisolated static let lastEvaluationSnapshotKey = "lastEvaluationSnapshot"

    /// The most recent successful evaluation result, or `nil` if none has been persisted.
    ///
    /// **Why persist this?** The dashboard seeds its UI from this snapshot on cold start,
    /// showing the last known steps/energy/blocking state instantly instead of zeros.
    /// Also used by `GoalGatekeeper` for anti-cheat decisions without a fresh HealthKit
    /// round-trip (the snapshot is at most seconds old after a foreground sync).
    nonisolated static var lastEvaluationSnapshot: EvaluationResult? {
        get {
            guard let data = appGroupDefaults.data(forKey: lastEvaluationSnapshotKey) else { return nil }
            return try? JSONDecoder().decode(EvaluationResult.self, from: data)
        }
        set {
            if let value = newValue, let data = try? JSONEncoder().encode(value) {
                appGroupDefaults.set(data, forKey: lastEvaluationSnapshotKey)
            } else {
                appGroupDefaults.removeObject(forKey: lastEvaluationSnapshotKey)
            }
        }
    }

    // MARK: - Mindful Peek

    /// Key for the `Date` when the active peek expires (shields re-apply).
    /// Must match `peekExpirationDateKey` in `TimeUnlockNames.swift` (extension target) —
    /// update both together if the key string ever needs to change.
    nonisolated static let peekExpirationDateKey = "peekExpirationDate"

    /// Key for the `Date` when the user activated their daily peek.
    /// Persisted separately from `peekExpirationDate` so the daily-limit check
    /// survives peek expiration (which nils the expiration date but must leave the
    /// activated flag for the remainder of the calendar day).
    private nonisolated static let peekActivatedDateKey = "peekActivatedDate"

    /// Duration of a Mindful Peek in seconds.
    nonisolated static let peekDurationSeconds: TimeInterval = 180

    /// When the currently active peek expires, or `nil` if no peek is active.
    nonisolated static var peekExpirationDate: Date? {
        get {
            let interval = appGroupDefaults.double(forKey: peekExpirationDateKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                appGroupDefaults.set(date.timeIntervalSince1970, forKey: peekExpirationDateKey)
            } else {
                appGroupDefaults.removeObject(forKey: peekExpirationDateKey)
            }
        }
    }

    /// When the user activated their daily peek, or `nil` if unused today.
    nonisolated static var peekActivatedDate: Date? {
        get {
            let interval = appGroupDefaults.double(forKey: peekActivatedDateKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                appGroupDefaults.set(date.timeIntervalSince1970, forKey: peekActivatedDateKey)
            } else {
                appGroupDefaults.removeObject(forKey: peekActivatedDateKey)
            }
        }
    }

    /// Whether a Mindful Peek is currently active (shields are temporarily lifted).
    nonisolated static var isPeekActive: Bool {
        guard let expiration = peekExpirationDate else { return false }
        return Date() < expiration
    }

    /// Whether the user's daily peek is still available (not yet used today).
    nonisolated static var isPeekAvailableToday: Bool {
        guard let activated = peekActivatedDate else { return true }
        return !Calendar.current.isDateInToday(activated)
    }

    /// Activates the daily Mindful Peek, recording the activation time and
    /// setting the expiration date.
    /// - Parameter duration: How long the peek lasts (defaults to `peekDurationSeconds`).
    nonisolated static func activatePeek(duration: TimeInterval = peekDurationSeconds) {
        let now = Date()
        peekActivatedDate = now
        peekExpirationDate = now.addingTimeInterval(duration)
    }

    /// Expires an active peek without resetting the daily-limit flag.
    ///
    /// **Why separate from `clearPeek()`?** When the timer runs out, we nil the
    /// expiration so `isPeekActive` returns false, but leave `peekActivatedDate` intact
    /// so the user cannot activate a second peek the same day.
    nonisolated static func expirePeek() {
        peekExpirationDate = nil
    }

    /// Resets all peek state for a new calendar day.
    /// Called during midnight rollover so the user gets a fresh daily peek.
    nonisolated static func clearPeek() {
        peekExpirationDate = nil
        peekActivatedDate = nil
    }
}
