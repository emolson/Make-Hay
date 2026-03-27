//
//  TimeUnlockScheduler.swift
//  Make Hay
//
//  Created by GitHub Copilot on 2/19/26.
//

import DeviceActivity
import Foundation

extension DeviceActivityName {
    /// Single daily time-unlock monitor.
    static let makeHayTimeUnlock = DeviceActivityName("makeHay.timeUnlock")
}

/// Protocol for scheduling time-based unlock monitoring.
protocol TimeUnlockScheduling: Sendable {
    /// Schedules a daily unlock monitor at the specified minutes since midnight.
    func scheduleUnlock(unlockMinutes: Int) throws
    /// Cancels any active unlock monitor.
    func cancelUnlock()
}

/// Live scheduler backed by `DeviceActivityCenter`.
struct DeviceActivityTimeUnlockScheduler: TimeUnlockScheduling {

    func scheduleUnlock(unlockMinutes: Int) throws {
        let center = DeviceActivityCenter()

        // Stop any existing monitor first
        cancelUnlock()

        let clampedMinutes = min(max(unlockMinutes, 0), (24 * 60) - 1)
        guard clampedMinutes > 0 else { return }

        let startHour = clampedMinutes / 60
        let startMinute = clampedMinutes % 60

        var start = DateComponents()
        start.hour = startHour
        start.minute = startMinute

        var end = DateComponents()
        end.hour = 23
        end.minute = 59

        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: true
        )

        try center.startMonitoring(.makeHayTimeUnlock, during: schedule)
    }

    func cancelUnlock() {
        DeviceActivityCenter().stopMonitoring([.makeHayTimeUnlock])
    }
}
