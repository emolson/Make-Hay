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
    private(set) var scheduledUnlockMinutes: Int?
    private(set) var cancelCallCount: Int = 0
    private(set) var scheduledPeekEndDate: Date?
    private(set) var cancelPeekEndCallCount: Int = 0

    func scheduleUnlock(unlockMinutes: Int) throws {
        scheduledUnlockMinutes = unlockMinutes
    }

    func cancelUnlock() {
        cancelCallCount += 1
        scheduledUnlockMinutes = nil
    }

    func schedulePeekEnd(at endDate: Date) throws {
        scheduledPeekEndDate = endDate
    }

    func cancelPeekEnd() {
        cancelPeekEndCallCount += 1
        scheduledPeekEndDate = nil
    }
}
