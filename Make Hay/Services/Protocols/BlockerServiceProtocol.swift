//
//  BlockerServiceProtocol.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import FamilyControls
import Foundation

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
}
