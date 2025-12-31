//
//  BlockerService.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import FamilyControls
import Foundation
import ManagedSettings

/// Actor responsible for managing Screen Time app blocking using FamilyControls and ManagedSettings.
///
/// **Why use an Actor?** FamilyControls and ManagedSettings involve shared mutable state
/// (the `ManagedSettingsStore` and persisted selection). Using an Actor ensures thread-safe
/// access to this state, preventing data races when called from multiple async contexts.
actor BlockerService: BlockerServiceProtocol {
    
    // MARK: - Properties
    
    /// The ManagedSettings store for applying/removing app shields.
    private let store = ManagedSettingsStore()
    
    /// The user's current app selection for blocking.
    private var selection: FamilyActivitySelection = FamilyActivitySelection()
    
    /// The file URL where the selection is persisted.
    private var selectionURL: URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsDirectory.appendingPathComponent("FamilyActivitySelection.plist")
    }
    
    // MARK: - Initialization
    
    init() {
        // Load persisted selection on initialization
        loadPersistedSelection()
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
        
        if shouldBlock {
            // Apply shields to the selected applications and categories
            store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
            store.shield.applicationCategories = selection.categoryTokens.isEmpty
                ? nil
                : ShieldSettings.ActivityCategoryPolicy.specific(selection.categoryTokens)
        } else {
            // Remove all shields to allow app access
            store.shield.applications = nil
            store.shield.applicationCategories = nil
        }
    }
    
    /// Stores the user's app selection and persists it to disk.
    ///
    /// **Why persist to a file?** The `FamilyActivitySelection` needs to survive app
    /// restarts so the blocking configuration remains intact. Since iOS 16+,
    /// `FamilyActivitySelection` conforms to `Codable`, allowing PropertyList encoding.
    ///
    /// - Parameter selection: The apps and categories selected for blocking.
    /// - Throws: `BlockerServiceError.shieldUpdateFailed` if persistence fails.
    func setSelection(_ selection: FamilyActivitySelection) async throws {
        self.selection = selection
        
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(selection)
            try data.write(to: selectionURL, options: .atomic)
        } catch {
            throw BlockerServiceError.shieldUpdateFailed(underlying: error)
        }
    }
    
    /// Retrieves the current app selection.
    /// - Returns: The stored `FamilyActivitySelection`, or an empty selection if none exists.
    func getSelection() async -> FamilyActivitySelection {
        return selection
    }
    
    // MARK: - Private Methods
    
    /// Loads the persisted selection from disk.
    ///
    /// Called during initialization to restore the user's previous app selection.
    /// If no file exists or decoding fails, the selection remains empty.
    private func loadPersistedSelection() {
        guard FileManager.default.fileExists(atPath: selectionURL.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: selectionURL)
            let decoder = PropertyListDecoder()
            selection = try decoder.decode(FamilyActivitySelection.self, from: data)
        } catch {
            // If loading fails, start with an empty selection
            // This is intentionally silent - the user can re-select apps
            selection = FamilyActivitySelection()
        }
    }
}
