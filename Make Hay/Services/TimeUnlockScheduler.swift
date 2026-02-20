//
//  TimeUnlockScheduler.swift
//  Make Hay
//
//  Created by GitHub Copilot on 2/19/26.
//

import DeviceActivity
import Foundation

extension DeviceActivityName {
    /// Daily monitor that starts at the configured unlock time.
    static let makeHayTimeUnlock = Self("makeHay.timeUnlock")
}

/// Protocol for scheduling time-based unlock monitoring.
protocol TimeUnlockScheduling {
    func scheduleDailyUnlock(at unlockMinutes: Int) throws
    func cancelDailyUnlock()
}

/// Live scheduler backed by `DeviceActivityCenter`.
struct DeviceActivityTimeUnlockScheduler: TimeUnlockScheduling {
    func scheduleDailyUnlock(at unlockMinutes: Int) throws {
        let clampedMinutes = min(max(unlockMinutes, 0), (24 * 60) - 1)
        let startHour = clampedMinutes / 60
        let startMinute = clampedMinutes % 60

        let start = DateComponents(hour: startHour, minute: startMinute)
        let end = DateComponents(hour: 23, minute: 59)

        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: true
        )

        try DeviceActivityCenter().startMonitoring(.makeHayTimeUnlock, during: schedule)
    }

    func cancelDailyUnlock() {
        DeviceActivityCenter().stopMonitoring([.makeHayTimeUnlock])
    }
}
