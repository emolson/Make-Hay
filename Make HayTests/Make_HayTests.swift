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

    @Test @MainActor func loadGoalsKeepsDashboardUsableWhenSyncReturnsEmptyMetrics() async {
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
        viewModel.errorMessage = "Previous sync error"

        await viewModel.loadGoals(reason: "dashboard.emptyMetrics")

        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.hasError == false)
        #expect(viewModel.currentSteps == 0)
        #expect(viewModel.currentActiveEnergy == 0)
        #expect(viewModel.isBlocking)
        #expect(viewModel.isLoading == false)
        #expect(await monitor.syncNowCallCount == 1)
    }

    @Test @MainActor func activatePeekFailsClosedWhenBackupMonitorSchedulingFails() async throws {
        SharedStorage.clearPeek()
        SharedStorage.resetPeekRestoreDiagnostics()
        SharedStorage.peekShieldEpoch = 0
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
            SharedStorage.peekShieldEpoch = 0
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
        SharedStorage.peekShieldEpoch = 0
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
            SharedStorage.peekShieldEpoch = 0
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

    /// Verifies that `activatePeek()` commits peek state to SharedStorage BEFORE it
    /// clears shields, so that any concurrent background health evaluation that fires
    /// during activation sees `isPeekActive=true` and knows not to re-block.
    ///
    /// This guards against Race 1: background eval reads isPeekActive=false (old order),
    /// computes shouldBlock=true, and re-blocks over the just-cleared shields.
    @Test @MainActor func activatePeekWritesStorageBeforeClearingShields() async throws {
        SharedStorage.clearPeek()
        SharedStorage.resetPeekRestoreDiagnostics()
        SharedStorage.peekShieldEpoch = 0
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
            SharedStorage.peekShieldEpoch = 0
        }

        let blockerService = MockBlockerService()
        let viewModel = DashboardViewModel(
            healthService: MockHealthService(),
            blockerService: blockerService,
            backgroundHealthMonitor: MockBackgroundHealthMonitor(),
            timeUnlockScheduler: MockTimeUnlockScheduler()
        )

        let result = await viewModel.activatePeek()

        #expect(result == .activated)
        // When updateShields(false) was called, SharedStorage.isPeekActive must
        // have already been true (expiration written before shield-clear).
        #expect(await blockerService.getIsPeekActiveAtLastShieldClear() == true)
    }

    @Test @MainActor func activatePeekSupportsDeveloperBypassDurationWithoutUsingQuota()
        async throws
    {
        SharedStorage.clearPeek()
        SharedStorage.resetPeekRestoreDiagnostics()
        SharedStorage.peekShieldEpoch = 0
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
            SharedStorage.peekShieldEpoch = 0
        }

        let blockerService = MockBlockerService()
        let scheduler = MockTimeUnlockScheduler()
        let viewModel = DashboardViewModel(
            healthService: MockHealthService(),
            blockerService: blockerService,
            backgroundHealthMonitor: MockBackgroundHealthMonitor(),
            timeUnlockScheduler: scheduler
        )

        let result = await viewModel.activatePeek(
            duration: 30,
            consumesUsageCount: false
        )

        #expect(result == .activated)
        #expect(viewModel.isPeekActive)
        #expect(SharedStorage.peekUsageCountToday == 0)
        #expect(SharedStorage.peekActivatedDate == nil)
        #expect(await blockerService.getIsBlocking() == false)

        if let expiration = SharedStorage.peekExpirationDate {
            let remaining = expiration.timeIntervalSinceNow
            #expect(remaining > 0)
            #expect(remaining <= 30)
        } else {
            Issue.record("Expected developer bypass to persist an expiration date.")
        }

        #expect(scheduler.scheduledPeekEndDate == SharedStorage.peekExpirationDate)
    }

    @Test @MainActor func refreshBlockingStateUpdatesBlockingWithoutDashboardLoadingUI()
        async throws
    {
        SharedStorage.clearPeek()
        SharedStorage.resetPeekRestoreDiagnostics()
        SharedStorage.peekShieldEpoch = 0
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
            SharedStorage.peekShieldEpoch = 0
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
        SharedStorage.peekShieldEpoch = 0
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
            SharedStorage.peekShieldEpoch = 0
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
        SharedStorage.peekShieldEpoch = 0
        defer {
            SharedStorage.clearPeek()
            SharedStorage.resetPeekRestoreDiagnostics()
            SharedStorage.peekShieldEpoch = 0
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
