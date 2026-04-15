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

    /// One-shot monitor that fires when a Mindful Peek expires.
    static let makeHayPeekEnd = DeviceActivityName("makeHay.peekEnd")
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

    func schedulePeekEnd(at endDate: Date) throws {
        let center = DeviceActivityCenter()
        cancelPeekEnd()

        // DeviceActivitySchedule is minute-granular — the `.second` component is
        // silently ignored. The foreground countdown timer is the primary enforcement
        // mechanism; this monitor is a secondary safety net for when the app is
        // backgrounded or killed during a peek.
        let start = Calendar.current.dateComponents([.hour, .minute], from: endDate)

        // End 1 minute after start — the interval only needs to fire `intervalDidStart`.
        let intervalEndDate = endDate.addingTimeInterval(60)
        let end = Calendar.current.dateComponents([.hour, .minute], from: intervalEndDate)

        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: false
        )

        try center.startMonitoring(.makeHayPeekEnd, during: schedule)
    }

    func cancelPeekEnd() {
        DeviceActivityCenter().stopMonitoring([.makeHayPeekEnd])
    }
}
