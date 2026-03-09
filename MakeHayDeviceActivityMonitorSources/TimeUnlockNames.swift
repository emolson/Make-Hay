//
//  TimeUnlockNames.swift
//  MakeHayDeviceActivityMonitorExtension
//
//  Created by GitHub Copilot on 2/19/26.
//

import DeviceActivity

extension DeviceActivityName {
    /// Per-weekday monitor name: `makeHay.timeUnlock.<weekday>`.
    /// Weekday values follow `Calendar.weekday`: 1 = Sunday … 7 = Saturday.
    static func makeHayWeekdayUnlock(_ weekday: Int) -> DeviceActivityName {
        Self("makeHay.timeUnlock.\(weekday)")
    }

    /// All 7 per-weekday activity names for bulk operations.
    static var allWeekdayUnlocks: [DeviceActivityName] {
        (1...7).map { makeHayWeekdayUnlock($0) }
    }
}
