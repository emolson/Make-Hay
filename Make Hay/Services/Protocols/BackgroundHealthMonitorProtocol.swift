//
//  BackgroundHealthMonitorProtocol.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/20/26.
//

import Foundation

/// Protocol defining the interface for background HealthKit observation.
///
/// **Why a separate protocol?** Decouples the observer/background-delivery concern from
/// data-fetching (`HealthServiceProtocol`). The monitor registers `HKObserverQuery`s and
/// `enableBackgroundDelivery` so HealthKit can wake the app when health data changes,
/// allowing goal evaluation and shield updates without user interaction.
protocol BackgroundHealthMonitorProtocol: Actor {
    /// Registers `HKObserverQuery` instances and enables background delivery for all
    /// tracked health types (steps, active energy, exercise time).
    ///
    /// Should be called once during app startup. Observer queries and
    /// `enableBackgroundDelivery` registrations do not persist across app terminations,
    /// so this must be called on every launch.
    func startMonitoring() async

    /// Stops all observer queries and disables background delivery.
    ///
    /// Typically called only during testing or app teardown.
    func stopMonitoring() async
}
