//
//  MockBlockerService.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import FamilyControls
import Foundation

/// Mock implementation of BlockerServiceProtocol for previews and unit tests.
/// Uses an Actor to maintain thread safety while allowing configurable behavior.
actor MockBlockerService: BlockerServiceProtocol {
    /// Tracks whether blocking is currently active.
    var isBlocking: Bool = false

    /// Records the value of `SharedStorage.isPeekActive` at the moment the most recent
    /// `updateShields(shouldBlock: false)` call was executed. Used to verify that
    /// activation commits peek state to SharedStorage before clearing shields.
    var isPeekActiveAtLastShieldClear: Bool = false

    /// Mock authorization state.
    var mockIsAuthorized: Bool = true

    /// When `true`, all methods will throw their respective errors.
    var shouldThrowError: Bool = false

    /// The stored app selection (simulates persistence).
    var selection: FamilyActivitySelection = FamilyActivitySelection()

    /// Cached serialized snapshot for read APIs.
    private var selectionSnapshot: AppSelectionSnapshot = .empty

    /// Returns the mock authorization status.
    var isAuthorized: Bool {
        mockIsAuthorized
    }

    /// Simulates requesting Family Controls authorization.
    /// - Throws: `BlockerServiceError.authorizationFailed` if `shouldThrowError` is `true`.
    func requestAuthorization() async throws {
        if shouldThrowError {
            throw BlockerServiceError.authorizationFailed
        }
    }

    /// Simulates updating shield status for selected apps.
    /// - Parameter shouldBlock: Whether apps should be blocked.
    /// - Throws: `BlockerServiceError.notAuthorized` if `shouldThrowError` is `true`.
    func updateShields(shouldBlock: Bool) async throws {
        if shouldThrowError {
            throw BlockerServiceError.notAuthorized
        }
        isBlocking = shouldBlock
        if !shouldBlock {
            isPeekActiveAtLastShieldClear = SharedStorage.isPeekActive
        }
    }

    /// Simulates storing the user's app selection.
    /// - Parameter selection: Serialized `FamilyActivitySelection` payload to store.
    /// - Throws: `BlockerServiceError.configurationUpdateFailed` if `shouldThrowError` is `true`.
    func setSelection(_ selection: AppSelectionSnapshot) async throws {
        if shouldThrowError {
            throw BlockerServiceError.configurationUpdateFailed
        }
        self.selection = try selection.decodedSelection()
        selectionSnapshot = selection
    }

    /// Returns the stored app selection.
    /// - Returns: The current selection as a serialized snapshot.
    func getSelection() async -> AppSelectionSnapshot {
        selectionSnapshot
    }

    /// Returns the current blocking state. Useful for test assertions.
    /// - Returns: `true` if blocking is active, `false` otherwise.
    func getIsBlocking() -> Bool {
        return isBlocking
    }

    /// Returns whether `SharedStorage.isPeekActive` was true when shields were last cleared.
    /// Used to verify activation ordering: SharedStorage must be written before shields are cleared.
    func getIsPeekActiveAtLastShieldClear() -> Bool {
        return isPeekActiveAtLastShieldClear
    }

    /// Configures whether the mock should throw errors.
    /// - Parameter shouldThrow: If `true`, methods will throw errors.
    func setShouldThrowError(_ shouldThrow: Bool) {
        shouldThrowError = shouldThrow
    }

    /// Configures the mock authorization state used by `isAuthorized`.
    /// - Parameter isAuthorized: Whether Screen Time should report as authorized.
    func setMockIsAuthorized(_ isAuthorized: Bool) {
        mockIsAuthorized = isAuthorized
    }

    private nonisolated static func snapshotOrEmpty(
        from selection: FamilyActivitySelection
    ) -> AppSelectionSnapshot {
        do {
            return try AppSelectionSnapshot(selection: selection)
        } catch {
            assertionFailure("Failed to encode mock FamilyActivitySelection snapshot.")
            return .empty
        }
    }
}
