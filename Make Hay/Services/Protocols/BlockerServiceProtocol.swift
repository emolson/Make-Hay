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
}
