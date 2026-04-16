//
//  Make_HayTests.swift
//  Make HayTests
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation
import Testing

@testable import Make_Hay

@Suite(.serialized)
struct Make_HayTests {

    @Test @MainActor func activatePeekFailsClosedWhenBackupMonitorSchedulingFails() async throws {
        SharedStorage.clearPeek()
        SharedStorage.resetPeekRestoreDiagnostics()
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
        }

        let blockerService = MockBlockerService()
        let viewModel = DashboardViewModel(
            healthService: MockHealthService(),
            blockerService: blockerService,
            backgroundHealthMonitor: MockBackgroundHealthMonitor(),
            timeUnlockScheduler: FailingPeekTimeUnlockScheduler()
        )

        let result = await viewModel.activatePeek()

        if case .activated = result {
            Issue.record("Expected peek activation to fail when backup scheduling throws.")
        }
        #expect(viewModel.isPeekActive == false)
        #expect(viewModel.peekTimeRemaining == 0)
        #expect(SharedStorage.peekExpirationDate == nil)
        #expect(SharedStorage.peekUsageCountToday == 0)
        #expect(await blockerService.getIsBlocking())
    }

    @Test @MainActor func activatePeekClearsStaleWarningOnSuccess() async throws {
        SharedStorage.clearPeek()
        SharedStorage.resetPeekRestoreDiagnostics()
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
        }

        let blockerService = MockBlockerService()
        let scheduler = MockTimeUnlockScheduler()
        let viewModel = DashboardViewModel(
            healthService: MockHealthService(),
            blockerService: blockerService,
            backgroundHealthMonitor: MockBackgroundHealthMonitor(),
            timeUnlockScheduler: scheduler
        )
        viewModel.shieldWarning = "Stale warning"

        let result = await viewModel.activatePeek()

        #expect(result == .activated)
        #expect(viewModel.shieldWarning == nil)
        #expect(viewModel.isPeekActive)
        #expect(viewModel.peekTimeRemaining > 0)
        #expect(scheduler.scheduledPeekEndDate != nil)
        #expect(await blockerService.getIsBlocking() == false)
    }

    @Test @MainActor func refreshBlockingStateUpdatesBlockingWithoutDashboardLoadingUI()
        async throws
    {
        SharedStorage.clearPeek()
        SharedStorage.resetPeekRestoreDiagnostics()
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
        }

        let monitor = MockBackgroundHealthMonitor()
        await monitor.setStubbedResult(
            EvaluationResult(
                steps: 0,
                activeEnergy: 0,
                exerciseMinutesByGoalId: [:],
                shouldBlock: true,
                timestamp: Date()
            )
        )
        let viewModel = DashboardViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService(),
            backgroundHealthMonitor: monitor,
            timeUnlockScheduler: MockTimeUnlockScheduler()
        )
        viewModel.errorMessage = "Existing dashboard error"

        await viewModel.refreshBlockingState(reason: "settings.test")

        #expect(viewModel.isBlocking)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.errorMessage == "Existing dashboard error")
        #expect(await monitor.syncNowCallCount == 1)
    }

    @Test @MainActor func expirePeekFailsClosedWhenSyncThrows() async throws {
        SharedStorage.clearPeek()
        SharedStorage.resetPeekRestoreDiagnostics()
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
        }

        let blockerService = MockBlockerService()
        let monitor = MockBackgroundHealthMonitor()
        await monitor.setShouldThrowOnSync(true)
        let scheduler = MockTimeUnlockScheduler()
        let viewModel = DashboardViewModel(
            healthService: MockHealthService(),
            blockerService: blockerService,
            backgroundHealthMonitor: monitor,
            timeUnlockScheduler: scheduler
        )

        let result = await viewModel.activatePeek()
        #expect(result == .activated)

        await viewModel.expirePeek()

        #expect(viewModel.isPeekActive == false)
        #expect(await blockerService.getIsBlocking())
        #expect(scheduler.cancelPeekEndCallCount == 0)
        #expect(SharedStorage.lastPeekRestoreSource == .appFallback)
        #expect(SharedStorage.lastPeekRestoreOutcome == .applied)
    }

    @Test @MainActor func peekTimerExpiryDoesNotCancelItsOwnSync() async throws {
        SharedStorage.clearPeek()
        SharedStorage.resetPeekRestoreDiagnostics()
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
        }

        let blockerService = MockBlockerService()
        let monitor = MockBackgroundHealthMonitor()
        await monitor.setShouldRespectTaskCancellationDuringSync(true)
        await monitor.setStubbedResult(
            EvaluationResult(
                steps: 0,
                activeEnergy: 0,
                exerciseMinutesByGoalId: [:],
                shouldBlock: true,
                timestamp: Date()
            )
        )
        let scheduler = MockTimeUnlockScheduler()
        let viewModel = DashboardViewModel(
            healthService: MockHealthService(),
            blockerService: blockerService,
            backgroundHealthMonitor: monitor,
            timeUnlockScheduler: scheduler
        )

        let result = await viewModel.activatePeek()
        #expect(result == .activated)

        SharedStorage.peekExpirationDate = Date().addingTimeInterval(-1)
        try await Task.sleep(for: .seconds(2))

        #expect(viewModel.isPeekActive == false)
        #expect(await blockerService.getIsBlocking())
        #expect(await monitor.syncNowCallCount == 1)
        #expect(scheduler.cancelPeekEndCallCount == 1)
        #expect(SharedStorage.lastPeekRestoreSource == .healthSync)
        #expect(SharedStorage.lastPeekRestoreOutcome == .applied)
    }

}

@MainActor
private final class FailingPeekTimeUnlockScheduler: TimeUnlockScheduling, Sendable {
    func scheduleUnlock(unlockMinutes: Int) throws {}

    func cancelUnlock() {}

    func schedulePeekEnd(at endDate: Date) throws {
        throw FailingPeekTimeUnlockSchedulerError.unavailable
    }

    func cancelPeekEnd() {}
}

private enum FailingPeekTimeUnlockSchedulerError: Error {
    case unavailable
}
