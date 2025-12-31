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
    
    /// When `true`, all methods will throw their respective errors.
    var shouldThrowError: Bool = false
    
    /// The stored app selection (simulates persistence).
    var selection: FamilyActivitySelection = FamilyActivitySelection()
    
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
    }
    
    /// Simulates storing the user's app selection.
    /// - Parameter selection: The `FamilyActivitySelection` to store.
    /// - Throws: `BlockerServiceError.shieldUpdateFailed` if `shouldThrowError` is `true`.
    func setSelection(_ selection: FamilyActivitySelection) async throws {
        if shouldThrowError {
            throw BlockerServiceError.shieldUpdateFailed(
                underlying: NSError(domain: "MockError", code: 0)
            )
        }
        self.selection = selection
    }
    
    /// Returns the stored app selection.
    /// - Returns: The current `FamilyActivitySelection`.
    func getSelection() async -> FamilyActivitySelection {
        return selection
    }
    
    /// Returns the current blocking state. Useful for test assertions.
    /// - Returns: `true` if blocking is active, `false` otherwise.
    func getIsBlocking() -> Bool {
        return isBlocking
    }
    
    /// Configures whether the mock should throw errors.
    /// - Parameter shouldThrow: If `true`, methods will throw errors.
    func setShouldThrowError(_ shouldThrow: Bool) {
        shouldThrowError = shouldThrow
    }
}
