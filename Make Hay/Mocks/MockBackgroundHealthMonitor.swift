//
//  MockBackgroundHealthMonitor.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/20/26.
//

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

    /// When `true`, `syncNow()` will throw an error.
    var shouldThrowOnSync: Bool = false

    func startMonitoring() async {
        startMonitoringCalled = true
        startMonitoringCallCount += 1
    }

    func stopMonitoring() async {
        stopMonitoringCalled = true
        stopMonitoringCallCount += 1
    }

    func syncNow() async throws {
        syncNowCalled = true
        syncNowCallCount += 1
        if shouldThrowOnSync {
            throw NSError(
                domain: "MockBackgroundHealthMonitor",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Mock sync error"]
            )
        }
    }
}
