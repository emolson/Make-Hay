//
//  BlockerServiceProtocol.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import FamilyControls
import Foundation

/// Sendable wrapper around a serialized `FamilyActivitySelection`.
///
/// `FamilyActivitySelection` comes from `FamilyControls`, which still has gaps in
/// strict-concurrency annotations. Passing a serialized snapshot across actor
/// boundaries keeps the blocker-service API explicitly Sendable while preserving
/// the actor's internal use of the concrete FamilyControls type.
struct AppSelectionSnapshot: Sendable {
    let encodedSelection: Data

    /// Canonical empty snapshot used when the app needs a known-good fallback.
    nonisolated static let empty = Self.makeEmptySnapshot()

    nonisolated init(encodedSelection: Data) {
        self.encodedSelection = encodedSelection
    }

    nonisolated init(selection: FamilyActivitySelection) throws {
        self.encodedSelection = try PropertyListEncoder().encode(selection)
    }

    nonisolated func decodedSelection() throws -> FamilyActivitySelection {
        try PropertyListDecoder().decode(FamilyActivitySelection.self, from: encodedSelection)
    }

    private nonisolated static func makeEmptySnapshot() -> AppSelectionSnapshot {
        do {
            return try AppSelectionSnapshot(selection: FamilyActivitySelection())
        } catch {
            preconditionFailure("Failed to encode an empty FamilyActivitySelection snapshot.")
        }
    }
}

/// Scheduled blocked-app selection to apply at a future effective date.
struct PendingAppSelection: Sendable {
    let selection: AppSelectionSnapshot
    let effectiveDate: Date

    nonisolated init(selection: AppSelectionSnapshot, effectiveDate: Date) {
        self.selection = selection
        self.effectiveDate = effectiveDate
    }

    nonisolated init(selection: FamilyActivitySelection, effectiveDate: Date) throws {
        self.init(
            selection: try AppSelectionSnapshot(selection: selection),
            effectiveDate: effectiveDate
        )
    }

    func decodedSelection() throws -> FamilyActivitySelection {
        try selection.decodedSelection()
    }
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
    /// - Parameter selection: A serialized selection snapshot containing apps and categories to block.
    /// - Throws: `BlockerServiceError` if persistence fails.
    func setSelection(_ selection: AppSelectionSnapshot) async throws
    
    /// Retrieves the current app selection.
    /// - Returns: The stored selection as a sendable serialized snapshot.
    func getSelection() async -> AppSelectionSnapshot

    /// Stores a pending app selection to apply at the given effective date.
    /// - Parameters:
    ///   - selection: The blocked-app selection snapshot to apply in the future.
    ///   - effectiveDate: Date when the pending selection becomes active.
    /// - Throws: `BlockerServiceError` if persistence fails.
    func setPendingSelection(_ selection: AppSelectionSnapshot, effectiveDate: Date) async throws

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
