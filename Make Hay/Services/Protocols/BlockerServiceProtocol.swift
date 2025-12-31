//
//  BlockerServiceProtocol.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation

/// Protocol defining the interface for app blocking operations using FamilyControls.
/// Conforms to Actor for thread-safe access to shield management.
protocol BlockerServiceProtocol: Actor {
    /// Requests authorization for Family Controls.
    /// - Throws: `BlockerServiceError` if authorization fails.
    func requestAuthorization() async throws
    
    /// Updates the shield status for selected apps.
    /// - Parameter shouldBlock: If `true`, applies shields to block selected apps.
    ///                          If `false`, removes shields to allow app access.
    /// - Throws: `BlockerServiceError` if the shield update fails.
    func updateShields(shouldBlock: Bool) async throws
}
