//
//  MockBackgroundHealthMonitor.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/20/26.
//

import BackgroundTasks
import Foundation

/// Mock implementation of `BackgroundHealthMonitorProtocol` for previews and unit tests.
///
/// **Why Actor?** Matches the real implementation's actor isolation, ensuring tests
/// exercise the same concurrency semantics.
actor MockBackgroundHealthMonitor: BackgroundHealthMonitorProtocol {
    /// Whether `startMonitoring()` has been called.
    private(set) var startMonitoringCalled: Bool = false

    /// Whether `stopMonitoring()` has been called.
    private(set) var stopMonitoringCalled: Bool = false

    /// The number of times `startMonitoring()` has been called.
    private(set) var startMonitoringCallCount: Int = 0

    /// The number of times `stopMonitoring()` has been called.
    private(set) var stopMonitoringCallCount: Int = 0

    /// Whether `syncNow()` has been called.
    private(set) var syncNowCalled: Bool = false

    /// The number of times `syncNow()` has been called.
    private(set) var syncNowCallCount: Int = 0

    /// Whether `handleBackgroundRefresh(task:)` has been called.
    private(set) var handleBackgroundRefreshCalled: Bool = false

    /// The number of times `handleBackgroundRefresh(task:)` has been called.
    private(set) var handleBackgroundRefreshCallCount: Int = 0

    /// When `true`, `syncNow()` will throw an error.
    var shouldThrowOnSync: Bool = false

    /// The result returned by `syncNow()`. Override this to simulate different health states.
    var stubbedResult: EvaluationResult = EvaluationResult(
        steps: 0,
        activeEnergy: 0,
        exerciseMinutesByGoalId: [:],
        shouldBlock: false,
        timestamp: Date()
    )

    func startMonitoring() async {
        startMonitoringCalled = true
        startMonitoringCallCount += 1
    }

    func stopMonitoring() async {
        stopMonitoringCalled = true
        stopMonitoringCallCount += 1
    }

    func setShouldThrowOnSync(_ shouldThrow: Bool) {
        shouldThrowOnSync = shouldThrow
    }

    func setStubbedResult(_ result: EvaluationResult) {
        stubbedResult = result
    }

    @discardableResult
    func syncNow(reason: String) async throws -> EvaluationResult {
        syncNowCalled = true
        syncNowCallCount += 1
        if shouldThrowOnSync {
            throw NSError(
                domain: "MockBackgroundHealthMonitor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Mock sync error"]
            )
        }
        return stubbedResult
    }

    func handleBackgroundRefresh(task: BGAppRefreshTask) async {
        handleBackgroundRefreshCalled = true
        handleBackgroundRefreshCallCount += 1
        task.setTaskCompleted(success: true)
    }
}
