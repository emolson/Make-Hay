//
//  BlockerServiceProtocol.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import FamilyControls
import Foundation

/// Scheduled blocked-app selection to apply at a future effective date.
struct PendingAppSelection: Sendable {
    let selection: FamilyActivitySelection
    let effectiveDate: Date
}

/// Protocol defining the interface for app blocking operations using FamilyControls.
/// Conforms to Actor for thread-safe access to shield management.
protocol BlockerServiceProtocol: Actor {
    /// Returns whether Family Controls is currently authorized.
    /// - Returns: `true` if authorized, `false` otherwise.
    var isAuthorized: Bool { get }
    
    /// Requests authorization for Family Controls.
    /// - Throws: `BlockerServiceError` if authorization fails.
    func requestAuthorization() async throws
    
    /// Updates the shield status for selected apps.
    /// - Parameter shouldBlock: If `true`, applies shields to block selected apps.
    ///                          If `false`, removes shields to allow app access.
    /// - Throws: `BlockerServiceError` if the shield update fails.
    func updateShields(shouldBlock: Bool) async throws
    
    /// Stores the user's app selection for blocking.
    /// - Parameter selection: The `FamilyActivitySelection` containing apps and categories to block.
    /// - Throws: `BlockerServiceError` if persistence fails.
    func setSelection(_ selection: FamilyActivitySelection) async throws
    
    /// Retrieves the current app selection.
    /// - Returns: The stored `FamilyActivitySelection`, or an empty selection if none exists.
    func getSelection() async -> FamilyActivitySelection

    /// Stores a pending app selection to apply at the given effective date.
    /// - Parameters:
    ///   - selection: The blocked-app selection to apply in the future.
    ///   - effectiveDate: Date when the pending selection becomes active.
    /// - Throws: `BlockerServiceError` if persistence fails.
    func setPendingSelection(_ selection: FamilyActivitySelection, effectiveDate: Date) async throws

    /// Retrieves the currently scheduled pending app selection, if any.
    /// - Returns: The pending selection payload and effective date.
    func getPendingSelection() async -> PendingAppSelection?

    /// Applies pending selection if its effective date has passed.
    /// - Returns: `true` if pending selection was applied; otherwise `false`.
    /// - Throws: `BlockerServiceError` if persistence fails.
    @discardableResult
    func applyPendingSelectionIfReady() async throws -> Bool

    /// Cancels any pending app selection.
    func cancelPendingSelection() async
}
