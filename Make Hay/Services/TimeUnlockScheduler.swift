//
//  TimeUnlockScheduler.swift
//  Make Hay
//
//  Created by GitHub Copilot on 2/19/26.
//

import DeviceActivity
import Foundation

extension DeviceActivityName {
    /// Daily monitor that starts at the configured unlock time (legacy, single-schedule).
    static let makeHayTimeUnlock = Self("makeHay.timeUnlock")

    /// Per-weekday monitors: `makeHay.timeUnlock.1` (Sunday) … `makeHay.timeUnlock.7` (Saturday).
    ///
    /// **Why per-weekday?** The weekly schedule allows different unlock times on each day.
    /// Each weekday gets its own `DeviceActivitySchedule` so the OS fires the correct one.
    static func makeHayWeekdayUnlock(_ weekday: Int) -> DeviceActivityName {
        Self("makeHay.timeUnlock.\(weekday)")
    }

    /// All 7 per-weekday activity names for bulk stop operations.
    static var allWeekdayUnlocks: [DeviceActivityName] {
        (1...7).map { makeHayWeekdayUnlock($0) }
    }
}

/// Describes a single weekday's unlock schedule entry.
struct WeekdayUnlockEntry: Sendable {
    let weekday: Int          // Calendar.weekday: 1 = Sunday … 7 = Saturday
    let unlockMinutes: Int    // Minutes since midnight
}

/// Protocol for scheduling time-based unlock monitoring.
protocol TimeUnlockScheduling: Sendable {
    /// Schedules a single daily unlock (legacy convenience, wraps `scheduleWeeklyUnlocks`).
    func scheduleDailyUnlock(at unlockMinutes: Int) throws
    /// Cancels all unlock monitors.
    func cancelDailyUnlock()

    /// Schedules per-weekday unlock monitors for each entry.
    ///
    /// **Why replace the single schedule?** The weekly model needs different unlock
    /// times per day. Each entry becomes a separate `DeviceActivitySchedule` keyed
    /// to `makeHay.timeUnlock.<weekday>`.
    func scheduleWeeklyUnlocks(_ entries: [WeekdayUnlockEntry]) throws
    /// Cancels all per-weekday unlock monitors.
    func cancelWeeklyUnlocks()
}

/// Live scheduler backed by `DeviceActivityCenter`.
struct DeviceActivityTimeUnlockScheduler: TimeUnlockScheduling {

    // MARK: - Legacy Single Schedule

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

    // MARK: - Weekly Schedule

    func scheduleWeeklyUnlocks(_ entries: [WeekdayUnlockEntry]) throws {
        let center = DeviceActivityCenter()

        // Stop all existing per-weekday monitors first
        cancelWeeklyUnlocks()
        // Also cancel legacy single monitor
        cancelDailyUnlock()

        for entry in entries {
            let clampedMinutes = min(max(entry.unlockMinutes, 0), (24 * 60) - 1)
            guard clampedMinutes > 0 else { continue } // 0 means instantly met; skip scheduling

            let startHour = clampedMinutes / 60
            let startMinute = clampedMinutes % 60

            // Build weekday-specific DateComponents so the schedule only fires on this day.
            var start = DateComponents()
            start.weekday = entry.weekday
            start.hour = startHour
            start.minute = startMinute

            var end = DateComponents()
            end.weekday = entry.weekday
            end.hour = 23
            end.minute = 59

            let schedule = DeviceActivitySchedule(
                intervalStart: start,
                intervalEnd: end,
                repeats: true
            )

            try center.startMonitoring(.makeHayWeekdayUnlock(entry.weekday), during: schedule)
        }
    }

    func cancelWeeklyUnlocks() {
        DeviceActivityCenter().stopMonitoring(DeviceActivityName.allWeekdayUnlocks)
    }
}
