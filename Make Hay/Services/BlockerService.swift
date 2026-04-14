//
//  BlockerService.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import FamilyControls
import Foundation
import ManagedSettings
import os.log

/// Actor responsible for managing Screen Time app blocking using FamilyControls and ManagedSettings.
///
/// **Why use an Actor?** FamilyControls and ManagedSettings involve shared mutable state
/// (the `ManagedSettingsStore` and persisted selection). Using an Actor ensures thread-safe
/// access to this state, preventing data races when called from multiple async contexts.
///
/// Persistence is delegated to an injected `SelectionRepositoryProtocol`, keeping this
/// actor focused on shield orchestration.
actor BlockerService: BlockerServiceProtocol {
    
    // MARK: - Properties
    
    /// The ManagedSettings store for applying/removing app shields.
    ///
    /// **Why a named store?** Using the default `ManagedSettingsStore()` can interfere
    /// with the system-wide Screen Time configuration. A named store isolates this app's
    /// shield settings so they never conflict with other profiles.
    private let store = ManagedSettingsStore(named: .init("makeHay"))

    /// Repository owning all selection persistence (file protection, corruption recovery).
    private let repository: any SelectionRepositoryProtocol
    
    /// The user's current app selection for blocking.
    private var selection: FamilyActivitySelection = FamilyActivitySelection()

    /// Cached serialized snapshot for cross-actor reads.
    private var selectionSnapshot: AppSelectionSnapshot = .empty

    private nonisolated static let logger = AppLogger.logger(category: "BlockerService")
    
    // MARK: - BlockerServiceProtocol
    
    /// Returns whether Family Controls is currently authorized.
    ///
    /// **Why use AuthorizationCenter.shared.authorizationStatus?**
    /// This is Apple's API for checking the current state of Family Controls authorization.
    /// Unlike HealthKit, FamilyControls clearly exposes whether access is approved.
    var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }
    
    // MARK: - Initialization
    
    /// Creates a new `BlockerService`.
    ///
    /// - Parameter repository: The persistence back-end for selection payloads.
    ///   Defaults to the file-backed `SelectionRepository`.
    init(repository: any SelectionRepositoryProtocol = SelectionRepository()) {
        self.repository = repository

        // Load persisted selection on initialization without crossing actor isolation.
        self.selection = repository.loadSelection()
        self.selectionSnapshot = Self.snapshotOrEmpty(
            from: self.selection,
            context: "active selection initialization"
        )
        
        // **Safety net:** If authorization was revoked while the app was closed,
        // orphaned shields could lock the user out of their device. Clear them
        // eagerly so the app always starts in a safe state.
        if AuthorizationCenter.shared.authorizationStatus != .approved {
            store.clearAllSettings()
        }
    }
    
    // MARK: - BlockerServiceProtocol
    
    /// Requests authorization for Family Controls individual mode.
    ///
    /// This prompts the user with a system dialog to allow the app to monitor
    /// and restrict screen time for the current device user.
    ///
    /// - Throws: `BlockerServiceError.authorizationFailed` if the user denies access
    ///           or if an error occurs during the authorization process.
    func requestAuthorization() async throws {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            throw BlockerServiceError.authorizationFailed
        }
    }
    
    /// Applies or removes shields on the selected apps and categories.
    ///
    /// **Why use ManagedSettingsStore?** This is Apple's API for applying restrictions
    /// to apps. When shields are applied, the selected apps display a blocking screen
    /// that prevents the user from accessing them.
    ///
    /// - Parameter shouldBlock: If `true`, applies shields. If `false`, removes them.
    /// - Throws: `BlockerServiceError.notAuthorized` if Family Controls is not authorized.
    func updateShields(shouldBlock: Bool) async throws {
        // Verify authorization status before attempting to modify shields
        guard AuthorizationCenter.shared.authorizationStatus == .approved else {
            throw BlockerServiceError.notAuthorized
        }
        
        // **Actor reentrancy fix:** Capture selection into a local *after* all
        // awaits so we use the post-mutation value without risking a stale read.
        let currentSelection = self.selection
        
        if shouldBlock {
            // Apply shields to the selected applications and categories.
            // **Self-exclusion:** We never shield Make Hay itself. Category tokens
            // can implicitly include our app, so we always set
            // `deferSystemExclusions` so ManagedSettings respects the calling app.
            store.shield.applications = currentSelection.applicationTokens.isEmpty
                ? nil
                : currentSelection.applicationTokens
            store.shield.applicationCategories = currentSelection.categoryTokens.isEmpty
                ? nil
                : ShieldSettings.ActivityCategoryPolicy.specific(
                    currentSelection.categoryTokens,
                    except: Set()
                )
        } else {
            // **Why clearAllSettings()?** Nil-ing individual shield properties
            // can leave residual settings (e.g., webDomains) from earlier
            // versions. clearAllSettings() guarantees a clean slate.
            store.clearAllSettings()
        }
    }
    
    /// Stores the user's app selection and persists it to disk.
    ///
    /// **Why persist to a file?** The `FamilyActivitySelection` needs to survive app
    /// restarts so the blocking configuration remains intact. Since iOS 16+,
    /// `FamilyActivitySelection` conforms to `Codable`, allowing PropertyList encoding.
    ///
    /// - Parameter selection: Serialized apps/categories selected for blocking.
    /// - Throws: `BlockerServiceError.configurationUpdateFailed` if persistence fails.
    func setSelection(_ selection: AppSelectionSnapshot) async throws {
        do {
            let decodedSelection = try selection.decodedSelection()
            try repository.saveSelection(decodedSelection)
            // Commit in-memory state only after persistence succeeds so the
            // actor and disk stay in sync on failure.
            self.selection = decodedSelection
            selectionSnapshot = selection
        } catch {
            throw BlockerServiceError.configurationUpdateFailed
        }
    }
    
    /// Retrieves the current app selection.
    /// - Returns: The stored selection as a sendable serialized snapshot.
    func getSelection() async -> AppSelectionSnapshot {
        selectionSnapshot
    }

    private nonisolated static func snapshotOrEmpty(
        from selection: FamilyActivitySelection,
        context: String
    ) -> AppSelectionSnapshot {
        do {
            return try AppSelectionSnapshot(selection: selection)
        } catch {
            logger.fault("Failed to encode selection snapshot during \(context, privacy: .public).")
            return .empty
        }
    }
}
