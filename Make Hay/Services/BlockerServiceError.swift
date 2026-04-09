//
//  BlockerServiceError.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation

/// Errors that can occur during Screen Time blocking operations.
enum BlockerServiceError: Error, Sendable {
    /// Authorization for Family Controls failed.
    case authorizationFailed

    /// Failed to update persisted blocking configuration.
    case configurationUpdateFailed
    
    /// The app is not authorized to use Family Controls.
    case notAuthorized
}

extension BlockerServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .authorizationFailed:
            return String(localized: "Failed to authorize Screen Time access.")
        case .configurationUpdateFailed:
            return String(localized: "Failed to update app blocking.")
        case .notAuthorized:
            return String(localized: "Screen Time access has not been authorized.")
        }
    }
}
