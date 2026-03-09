//
//  MockTimeUnlockScheduler.swift
//  Make Hay
//
//  Created by GitHub Copilot on 2/19/26.
//

import Foundation

/// Mock implementation of `TimeUnlockScheduling` for previews and tests.
///
/// **Why `@MainActor` instead of `@unchecked Sendable`?** The mutable stored properties
/// in this mock have no internal synchronization.
/// `@MainActor` isolation provides proper Swift 6 strict concurrency safety and is
/// appropriate since this mock is only consumed in `@MainActor` contexts (previews,
/// `DashboardViewModel`). The protocol methods are synchronous, which prevents using
/// a plain `actor` (would require `nonisolated` on every method, defeating the purpose).
@MainActor
final class MockTimeUnlockScheduler: TimeUnlockScheduling, Sendable {
    private(set) var scheduledWeeklyEntries: [WeekdayUnlockEntry] = []
    private(set) var cancelWeeklyCallCount: Int = 0

    func scheduleWeeklyUnlocks(_ entries: [WeekdayUnlockEntry]) throws {
        scheduledWeeklyEntries = entries
    }

    func cancelWeeklyUnlocks() {
        cancelWeeklyCallCount += 1
        scheduledWeeklyEntries = []
    }
}
