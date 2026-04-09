//
//  PermissionManaging.swift
//  Make Hay
//
//  Created by GitHub Copilot on 4/8/26.
//

/// Capability-oriented protocol for the shared permission state manager.
///
/// Views still inject the concrete `PermissionManager` through the SwiftUI environment
/// so Observation can track property reads. This protocol exists for non-view consumers
/// and tests that only need the permission-management surface area.
@MainActor
protocol PermissionManaging: AnyObject {
    var healthAuthorizationStatus: HealthAuthorizationStatus { get }
    var healthAuthorizationPromptShown: Bool { get }
    var screenTimeAuthorized: Bool { get }
    var isPermissionMissing: Bool { get }

    func refresh() async
    func requestHealthPermission() async throws -> HealthAuthorizationStatus
    func requestScreenTimePermission() async throws
}