//
//  TimeUnlockScheduling.swift
//  Make Hay
//
//  Created by GitHub Copilot on 4/8/26.
//

/// Protocol for scheduling time-based unlock monitoring.
protocol TimeUnlockScheduling: Sendable {
    /// Schedules a daily unlock monitor at the specified minutes since midnight.
    func scheduleUnlock(unlockMinutes: Int) throws
    /// Cancels any active unlock monitor.
    func cancelUnlock()
}