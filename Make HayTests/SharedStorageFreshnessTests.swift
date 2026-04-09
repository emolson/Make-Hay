//
//  SharedStorageFreshnessTests.swift
//  Make HayTests
//
//  Created by GitHub Copilot on 4/8/26.
//

import Foundation
import Testing
@testable import Make_Hay

/// Tests for the evaluation freshness metadata in `SharedStorage`.
///
/// **Why serialized?** All tests read and write the same App Group UserDefaults keys.
/// Running in parallel causes data races between setup/teardown. Swift Testing's
/// `.serialized` trait prevents this without introducing per-test key namespacing.
@Suite(.serialized)
struct SharedStorageFreshnessTests {

    // MARK: - Setup

    /// Clears all freshness keys so tests start from a clean slate.
    private func resetFreshnessState() {
        SharedStorage.lastEvaluationDate = nil
        SharedStorage.lastEvaluationSource = nil
        SharedStorage.lastEvaluationFailure = nil
        SharedStorage.appGroupDefaults.synchronize()
    }

    // MARK: - Staleness Threshold

    @Test func isStaleWhenNoEvaluationRecorded() {
        resetFreshnessState()
        #expect(SharedStorage.isEvaluationStale)
    }

    @Test func isNotStaleImmediatelyAfterSuccess() {
        resetFreshnessState()
        SharedStorage.recordEvaluationSuccess(source: .observer)
        #expect(!SharedStorage.isEvaluationStale)
    }

    @Test func isStaleAfterThresholdPasses() {
        resetFreshnessState()
        // Place the last evaluation just past the threshold.
        let pastDate = Date().addingTimeInterval(-(SharedStorage.stalenessThresholdSeconds + 1))
        SharedStorage.lastEvaluationDate = pastDate
        #expect(SharedStorage.isEvaluationStale)
    }

    @Test func isNotStaleJustBeforeThreshold() {
        resetFreshnessState()
        let recentDate = Date().addingTimeInterval(-(SharedStorage.stalenessThresholdSeconds - 60))
        SharedStorage.lastEvaluationDate = recentDate
        #expect(!SharedStorage.isEvaluationStale)
    }

    // MARK: - Success Recording

    @Test func recordSuccessSetsDateSourceAndClearsFailure() {
        resetFreshnessState()
        SharedStorage.lastEvaluationFailure = "previous failure"

        SharedStorage.recordEvaluationSuccess(source: .manualSync)

        #expect(SharedStorage.lastEvaluationDate != nil)
        #expect(SharedStorage.lastEvaluationSource == .manualSync)
        #expect(SharedStorage.lastEvaluationFailure == nil)
    }

    @Test func recordSuccessPreservesSourceIdentity() {
        resetFreshnessState()
        SharedStorage.recordEvaluationSuccess(source: .foregroundFallback)
        #expect(SharedStorage.lastEvaluationSource == .foregroundFallback)

        SharedStorage.recordEvaluationSuccess(source: .observer)
        #expect(SharedStorage.lastEvaluationSource == .observer)
    }

    // MARK: - Failure Recording

    @Test func recordFailureSetsDescriptionWithoutUpdatingDate() {
        resetFreshnessState()
        let fixedDate = Date().addingTimeInterval(-600)
        SharedStorage.lastEvaluationDate = fixedDate

        SharedStorage.recordEvaluationFailure(.timeout)

        #expect(SharedStorage.lastEvaluationFailure == "timeout")
        // Date should remain unchanged.
        let storedInterval = SharedStorage.lastEvaluationDate?.timeIntervalSince1970 ?? 0
        #expect(abs(storedInterval - fixedDate.timeIntervalSince1970) < 1)
    }

    @Test func successAfterFailureClearsFailureDescription() {
        resetFreshnessState()
        SharedStorage.recordEvaluationFailure(.unknown)
        #expect(SharedStorage.lastEvaluationFailure != nil)

        SharedStorage.recordEvaluationSuccess(source: .observer)
        #expect(SharedStorage.lastEvaluationFailure == nil)
    }

    // MARK: - Edge Cases

    @Test func clearingDateMakesEvaluationStale() {
        resetFreshnessState()
        SharedStorage.recordEvaluationSuccess(source: .observer)
        #expect(!SharedStorage.isEvaluationStale)

        SharedStorage.lastEvaluationDate = nil
        #expect(SharedStorage.isEvaluationStale)
    }
}
