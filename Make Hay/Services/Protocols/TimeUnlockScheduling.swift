//
//  TimeUnlockScheduling.swift
//  Make Hay
//
//  Created by GitHub Copilot on 4/8/26.
//

import Foundation

/// Protocol for scheduling time-based unlock monitoring.
protocol TimeUnlockScheduling: Sendable {
    /// Schedules a daily unlock monitor at the specified minutes since midnight.
    func scheduleUnlock(unlockMinutes: Int) throws
    /// Cancels any active unlock monitor.
    func cancelUnlock()

    /// Schedules a one-shot monitor that fires when a Mindful Peek expires.
    /// - Parameter endDate: The `Date` when shields should re-apply.
    func schedulePeekEnd(at endDate: Date) throws
    /// Cancels any active peek-end monitor.
    func cancelPeekEnd()
}
