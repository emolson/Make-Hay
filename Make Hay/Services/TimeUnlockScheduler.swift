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
        let scheduledFireDate = roundedUpToNextMinute(endDate)
        let start = oneShotDateComponents(for: scheduledFireDate)

        // DeviceActivitySchedule enforces a minimum 15-minute interval. The actual
        // peek re-lock fires at `intervalDidStart`, so a wider window is harmless —
        // it just keeps the monitor slot open longer.
        let intervalEndDate = scheduledFireDate.addingTimeInterval(16 * 60)
        let end = oneShotDateComponents(for: intervalEndDate)

        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: false
        )

        do {
            try center.startMonitoring(.makeHayPeekEnd, during: schedule)
            SharedStorage.recordPeekMonitorScheduled(
                expectedExpiration: endDate,
                scheduledFireDate: scheduledFireDate,
                scheduledIntervalEndDate: intervalEndDate
            )
        } catch {
            SharedStorage.recordPeekRestoreEvent(
                source: .scheduler,
                outcome: .failed,
                failure: .scheduleRejected
            )
            throw error
        }
    }

    func cancelPeekEnd() {
        DeviceActivityCenter().stopMonitoring([.makeHayPeekEnd])
    }

    /// Rounds a `Date` up to the next whole minute so the backup monitor never
    /// fires before the intended peek expiry.
    private func roundedUpToNextMinute(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let truncated = calendar.date(from: components) ?? date

        if truncated == date {
            return truncated
        }

        return calendar.date(byAdding: .minute, value: 1, to: truncated) ?? truncated
    }

    /// Produces a concrete, non-repeating schedule component set for DeviceActivity.
    private func oneShotDateComponents(for date: Date) -> DateComponents {
        Calendar.current.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: date
        )
    }
}
