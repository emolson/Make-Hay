//
//  MockTimeUnlockScheduler.swift
//  Make Hay
//
//  Created by GitHub Copilot on 2/19/26.
//

import Foundation

/// Mock implementation of `TimeUnlockScheduling` for previews and tests.
final class MockTimeUnlockScheduler: TimeUnlockScheduling, @unchecked Sendable {
    private(set) var scheduledUnlockMinutes: Int?
    private(set) var cancelCallCount: Int = 0
    private(set) var scheduledWeeklyEntries: [WeekdayUnlockEntry] = []
    private(set) var cancelWeeklyCallCount: Int = 0

    func scheduleDailyUnlock(at unlockMinutes: Int) throws {
        scheduledUnlockMinutes = unlockMinutes
    }

    func cancelDailyUnlock() {
        cancelCallCount += 1
        scheduledUnlockMinutes = nil
    }

    func scheduleWeeklyUnlocks(_ entries: [WeekdayUnlockEntry]) throws {
        scheduledWeeklyEntries = entries
    }

    func cancelWeeklyUnlocks() {
        cancelWeeklyCallCount += 1
        scheduledWeeklyEntries = []
    }
}
