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
    private nonisolated static let healthAuthorizationPromptShownKey =
        "healthAuthorizationPromptShown"

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

    /// Sources that can restore shields when a Mindful Peek expires.
    enum PeekRestoreSource: String, Sendable {
        case scheduler = "scheduler"
        case appFallback = "appFallback"
        case deviceActivityExtension = "extension"
        case healthSync = "healthSync"
    }

    /// Coarse outcomes for the most recent peek-expiry enforcement event.
    enum PeekRestoreOutcome: String, Sendable {
        case scheduled = "scheduled"
        case applied = "applied"
        case cleared = "cleared"
        case failed = "failed"
    }

    /// Stable failure codes for the peek-expiry restore path.
    enum PeekRestoreFailureReason: String, Sendable {
        case scheduleRejected = "scheduleRejected"
        case appGroupUnavailable = "appGroupUnavailable"
        case selectionMissing = "selectionMissing"
        case selectionDecodeFailed = "selectionDecodeFailed"
        case notAuthorized = "notAuthorized"
        case shieldUpdateFailed = "shieldUpdateFailed"
        case syncCancelled = "syncCancelled"
        case syncFailed = "syncFailed"
        case unknown = "unknown"
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
            guard let raw = appGroupDefaults.string(forKey: lastEvaluationSourceKey) else {
                return nil
            }
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
            guard let data = appGroupDefaults.data(forKey: lastEvaluationSnapshotKey) else {
                return nil
            }
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

    /// Key for the original expiration `Date` the app intended for the current peek.
    /// Preserved after expiry so the app can diagnose scheduler drift.
    nonisolated static let peekExpectedExpirationDateKey = "peekExpectedExpirationDate"

    /// Key for the rounded-up minute when the DeviceActivity monitor should fire.
    nonisolated static let peekMonitorScheduledFireDateKey = "peekMonitorScheduledFireDate"

    /// Key for the end of the one-shot DeviceActivity interval.
    nonisolated static let peekMonitorScheduledIntervalEndDateKey =
        "peekMonitorScheduledIntervalEndDate"

    /// Key for the timestamp of the last peek-expiry enforcement event.
    nonisolated static let peekRestoreEventDateKey = "peekRestoreEventDate"

    /// Key for the source of the last peek-expiry enforcement event.
    nonisolated static let peekRestoreSourceKey = "peekRestoreSource"

    /// Key for the outcome of the last peek-expiry enforcement event.
    nonisolated static let peekRestoreOutcomeKey = "peekRestoreOutcome"

    /// Key for the coarse failure reason of the last peek-expiry enforcement event.
    nonisolated static let peekRestoreFailureKey = "peekRestoreFailure"

    /// Key for the `Date` when the user last activated a peek.
    /// Used alongside the usage count to detect day rollovers.
    private nonisolated static let peekActivatedDateKey = "peekActivatedDate"

    /// Key for the number of peeks used today.
    private nonisolated static let peekUsageCountKey = "peekUsageCountToday"

    /// Tiered peek durations in seconds: 3 min → 2 min → 1 min for all subsequent.
    private nonisolated static let peekDurations: [TimeInterval] = [180, 120, 60]

    /// Returns the peek duration for the next activation based on today's usage count.
    nonisolated static var nextPeekDurationSeconds: TimeInterval {
        let count = peekUsageCountToday
        if count < peekDurations.count {
            return peekDurations[count]
        }
        return peekDurations.last!
    }

    /// Returns the peek duration in whole minutes for the next activation.
    nonisolated static var nextPeekDurationMinutes: Int {
        Int(nextPeekDurationSeconds) / 60
    }

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

    /// The app's intended expiration date for the current or most recent peek.
    nonisolated static var peekExpectedExpirationDate: Date? {
        get {
            let interval = appGroupDefaults.double(forKey: peekExpectedExpirationDateKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                appGroupDefaults.set(
                    date.timeIntervalSince1970, forKey: peekExpectedExpirationDateKey)
            } else {
                appGroupDefaults.removeObject(forKey: peekExpectedExpirationDateKey)
            }
        }
    }

    /// The rounded-up DeviceActivity start date for the current or most recent peek.
    nonisolated static var peekMonitorScheduledFireDate: Date? {
        get {
            let interval = appGroupDefaults.double(forKey: peekMonitorScheduledFireDateKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                appGroupDefaults.set(
                    date.timeIntervalSince1970, forKey: peekMonitorScheduledFireDateKey)
            } else {
                appGroupDefaults.removeObject(forKey: peekMonitorScheduledFireDateKey)
            }
        }
    }

    /// The end of the one-shot DeviceActivity interval for the current or most recent peek.
    nonisolated static var peekMonitorScheduledIntervalEndDate: Date? {
        get {
            let interval = appGroupDefaults.double(forKey: peekMonitorScheduledIntervalEndDateKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                appGroupDefaults.set(
                    date.timeIntervalSince1970,
                    forKey: peekMonitorScheduledIntervalEndDateKey
                )
            } else {
                appGroupDefaults.removeObject(forKey: peekMonitorScheduledIntervalEndDateKey)
            }
        }
    }

    /// When the last peek-expiry enforcement event happened.
    nonisolated static var lastPeekRestoreDate: Date? {
        get {
            let interval = appGroupDefaults.double(forKey: peekRestoreEventDateKey)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }
        set {
            if let date = newValue {
                appGroupDefaults.set(date.timeIntervalSince1970, forKey: peekRestoreEventDateKey)
            } else {
                appGroupDefaults.removeObject(forKey: peekRestoreEventDateKey)
            }
        }
    }

    /// The source of the last peek-expiry enforcement event.
    nonisolated static var lastPeekRestoreSource: PeekRestoreSource? {
        get {
            guard let raw = appGroupDefaults.string(forKey: peekRestoreSourceKey) else {
                return nil
            }
            return PeekRestoreSource(rawValue: raw)
        }
        set {
            if let value = newValue {
                appGroupDefaults.set(value.rawValue, forKey: peekRestoreSourceKey)
            } else {
                appGroupDefaults.removeObject(forKey: peekRestoreSourceKey)
            }
        }
    }

    /// The outcome of the last peek-expiry enforcement event.
    nonisolated static var lastPeekRestoreOutcome: PeekRestoreOutcome? {
        get {
            guard let raw = appGroupDefaults.string(forKey: peekRestoreOutcomeKey) else {
                return nil
            }
            return PeekRestoreOutcome(rawValue: raw)
        }
        set {
            if let value = newValue {
                appGroupDefaults.set(value.rawValue, forKey: peekRestoreOutcomeKey)
            } else {
                appGroupDefaults.removeObject(forKey: peekRestoreOutcomeKey)
            }
        }
    }

    /// The coarse failure reason for the last peek-expiry enforcement event.
    nonisolated static var lastPeekRestoreFailure: PeekRestoreFailureReason? {
        get {
            guard let raw = appGroupDefaults.string(forKey: peekRestoreFailureKey) else {
                return nil
            }
            return PeekRestoreFailureReason(rawValue: raw)
        }
        set {
            if let value = newValue {
                appGroupDefaults.set(value.rawValue, forKey: peekRestoreFailureKey)
            } else {
                appGroupDefaults.removeObject(forKey: peekRestoreFailureKey)
            }
        }
    }

    /// When the user last activated a peek, or `nil` if unused today.
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

    /// Number of peeks the user has activated today.
    nonisolated static var peekUsageCountToday: Int {
        get {
            guard let activated = peekActivatedDate,
                Calendar.current.isDateInToday(activated)
            else { return 0 }
            return appGroupDefaults.integer(forKey: peekUsageCountKey)
        }
        set {
            appGroupDefaults.set(newValue, forKey: peekUsageCountKey)
        }
    }

    /// Whether a Mindful Peek is currently active (shields are temporarily lifted).
    nonisolated static var isPeekActive: Bool {
        guard let expiration = peekExpirationDate else { return false }
        return Date() < expiration
    }

    /// Activates a Mindful Peek with a tiered duration based on today's usage count.
    nonisolated static func activatePeek() {
        let now = Date()
        let duration = nextPeekDurationSeconds
        resetPeekRestoreDiagnostics()
        peekActivatedDate = now
        peekUsageCountToday += 1
        peekExpirationDate = now.addingTimeInterval(duration)
        peekExpectedExpirationDate = peekExpirationDate
    }

    /// Expires an active peek without resetting the usage count.
    ///
    /// **Why separate from `clearPeek()`?** When the timer runs out, we nil the
    /// expiration so `isPeekActive` returns false, but leave the usage count intact
    /// so subsequent peeks use the correct tiered duration.
    nonisolated static func expirePeek() {
        peekExpirationDate = nil
    }

    /// Resets shared diagnostics for a brand-new peek activation.
    nonisolated static func resetPeekRestoreDiagnostics() {
        peekExpectedExpirationDate = nil
        peekMonitorScheduledFireDate = nil
        peekMonitorScheduledIntervalEndDate = nil
        lastPeekRestoreDate = nil
        lastPeekRestoreSource = nil
        lastPeekRestoreOutcome = nil
        lastPeekRestoreFailure = nil
    }

    /// Records the one-shot DeviceActivity monitor schedule used as the peek backup.
    nonisolated static func recordPeekMonitorScheduled(
        expectedExpiration: Date,
        scheduledFireDate: Date,
        scheduledIntervalEndDate: Date
    ) {
        peekExpectedExpirationDate = expectedExpiration
        peekMonitorScheduledFireDate = scheduledFireDate
        peekMonitorScheduledIntervalEndDate = scheduledIntervalEndDate
        recordPeekRestoreEvent(source: .scheduler, outcome: .scheduled)
    }

    /// Records the latest coarse peek-expiry enforcement event.
    nonisolated static func recordPeekRestoreEvent(
        source: PeekRestoreSource,
        outcome: PeekRestoreOutcome,
        failure: PeekRestoreFailureReason? = nil
    ) {
        lastPeekRestoreDate = Date()
        lastPeekRestoreSource = source
        lastPeekRestoreOutcome = outcome
        lastPeekRestoreFailure = failure
    }

    /// Resets all peek state for a new calendar day.
    /// Called during midnight rollover so the user gets fresh tiered peeks.
    nonisolated static func clearPeek() {
        peekExpirationDate = nil
        peekActivatedDate = nil
        peekUsageCountToday = 0
    }
}
