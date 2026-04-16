//
//  TimeUnlockNames.swift
//  MakeHayDeviceActivityMonitorExtension
//
//  Created by GitHub Copilot on 2/19/26.
//

import DeviceActivity

extension DeviceActivityName {
    /// Single daily time-unlock monitor.
    static let makeHayTimeUnlock = DeviceActivityName("makeHay.timeUnlock")

    /// One-shot monitor that fires when a Mindful Peek expires.
    static let makeHayPeekEnd = DeviceActivityName("makeHay.peekEnd")
}

/// UserDefaults key for the Mindful Peek expiration date (stored as `TimeInterval`).
/// Must match `SharedStorage.peekExpirationDateKey` in the app target — update both
/// together if the key string ever needs to change.
let peekExpirationDateKey = "peekExpirationDate"

/// UserDefaults key for the intended expiration date of the current or last peek.
let peekExpectedExpirationDateKey = "peekExpectedExpirationDate"

/// UserDefaults key for the rounded-up minute when the peek backup monitor should fire.
let peekMonitorScheduledFireDateKey = "peekMonitorScheduledFireDate"

/// UserDefaults key for the end of the one-shot peek backup interval.
let peekMonitorScheduledIntervalEndDateKey = "peekMonitorScheduledIntervalEndDate"

/// UserDefaults key for the timestamp of the last peek-expiry enforcement event.
let peekRestoreEventDateKey = "peekRestoreEventDate"

/// UserDefaults key for the source of the last peek-expiry enforcement event.
let peekRestoreSourceKey = "peekRestoreSource"

/// UserDefaults key for the outcome of the last peek-expiry enforcement event.
let peekRestoreOutcomeKey = "peekRestoreOutcome"

/// UserDefaults key for the coarse failure code of the last peek-expiry enforcement event.
let peekRestoreFailureKey = "peekRestoreFailure"
