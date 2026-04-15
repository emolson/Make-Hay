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
