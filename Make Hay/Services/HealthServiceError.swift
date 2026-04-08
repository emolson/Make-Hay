//
//  HealthServiceError.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation

/// Represents the authorization status for HealthKit access.
///
/// **Why a custom enum?** HealthKit's native `HKAuthorizationStatus` has privacy restrictions
/// that don't clearly indicate if the user approved access. We use a simplified status
/// that reflects the practical authorization state for our app's needs.
enum HealthAuthorizationStatus: Sendable {
    /// Authorization has not been requested yet.
    case notDetermined

    /// The HealthKit sheet has been shown, but readable data is not yet proven.
    case unconfirmed
    
    /// The user authorized access to health data.
    case authorized
    
    /// The user denied access or authorization is not possible.
    case denied

    /// Whether the app has verified readable Health data.
    var isAuthorized: Bool {
        self == .authorized
    }

    /// Whether the one-time HealthKit sheet has already been consumed.
    var promptHasBeenShown: Bool {
        switch self {
        case .notDetermined:
            false
        case .unconfirmed, .authorized, .denied:
            true
        }
    }

    /// Normalizes stale storage or mock states where the prompt was shown but access
    /// is still reported as `.notDetermined`.
    func normalized(promptShown: Bool) -> Self {
        if promptShown && self == .notDetermined {
            return .unconfirmed
        }

        return self
    }
}

/// Errors that can occur during HealthKit operations.
enum HealthServiceError: Error, Sendable {
    /// HealthKit is not available on this device (e.g., iPad without Health app).
    case healthKitNotAvailable
    
    /// The user denied authorization to read health data.
    case authorizationDenied
    
    /// A query to HealthKit failed.
    /// - Parameter description: The localized description of the underlying HealthKit error.
    case queryFailed(underlying: Error)
    
    /// A HealthKit query did not respond within the allowed timeout.
    ///
    /// **Why this case?** `withCheckedThrowingContinuation` wrapping HKQuery callbacks
    /// will hang forever if the HealthKit daemon is unresponsive. This bounded-timeout
    /// error prevents the UI from showing an infinite loading spinner.
    case queryTimedOut
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
        case .queryTimedOut:
            return String(localized: "Health data query timed out. Please try again.")
        }
    }
}
