//
//  HealthServiceError.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation

/// Errors that can occur during HealthKit operations.
enum HealthServiceError: Error, Sendable {
    /// HealthKit is not available on this device (e.g., iPad without Health app).
    case healthKitNotAvailable
    
    /// The user denied authorization to read health data.
    case authorizationDenied
    
    /// A query to HealthKit failed.
    /// - Parameter underlying: The underlying error from HealthKit.
    case queryFailed(underlying: Error)
}

extension HealthServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .healthKitNotAvailable:
            return String(localized: "Health data is not available on this device.")
        case .authorizationDenied:
            return String(localized: "Permission to access health data was denied.")
        case .queryFailed(let underlying):
            return String(localized: "Failed to fetch health data: \(underlying.localizedDescription)")
        }
    }
}
