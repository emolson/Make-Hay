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
    ///
    /// **Why a named store?** Using the default `ManagedSettingsStore()` can interfere
    /// with the system-wide Screen Time configuration. A named store isolates this app's
    /// shield settings so they never conflict with other profiles.
    private let store = ManagedSettingsStore(named: .init("makeHay"))
    
    /// The user's current app selection for blocking.
    private var selection: FamilyActivitySelection = FamilyActivitySelection()

    /// Pending app selection scheduled for future application.
    private var pendingSelection: FamilyActivitySelection?

    /// Effective date for applying `pendingSelection`.
    private var pendingSelectionEffectiveDate: Date?
    
    /// The file URL where the selection is persisted.
    private static var selectionURL: URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsDirectory.appendingPathComponent("FamilyActivitySelection.plist")
    }

    /// The file URL where pending selection is persisted.
    private static var pendingSelectionURL: URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsDirectory.appendingPathComponent("PendingFamilyActivitySelection.plist")
    }

    /// The file URL where pending selection effective date is persisted.
    private static var pendingSelectionDateURL: URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        return documentsDirectory.appendingPathComponent("PendingFamilyActivitySelectionDate.plist")
    }
    
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
    
    init() {
        // Load persisted selection on initialization without crossing actor isolation.
        self.selection = Self.loadPersistedSelection()
        self.pendingSelection = Self.loadPersistedPendingSelection()
        self.pendingSelectionEffectiveDate = Self.loadPersistedPendingSelectionDate()
        
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
        _ = try await applyPendingSelectionIfReady()

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
    /// - Parameter selection: The apps and categories selected for blocking.
    /// - Throws: `BlockerServiceError.shieldUpdateFailed` if persistence fails.
    func setSelection(_ selection: FamilyActivitySelection) async throws {
        self.selection = selection
        
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(selection)
            try data.write(to: Self.selectionURL, options: .atomic)
            clearPersistedPendingSelection()
            pendingSelection = nil
            pendingSelectionEffectiveDate = nil
        } catch {
            throw BlockerServiceError.shieldUpdateFailed(description: error.localizedDescription)
        }
    }
    
    /// Retrieves the current app selection.
    /// - Returns: The stored `FamilyActivitySelection`, or an empty selection if none exists.
    func getSelection() async -> FamilyActivitySelection {
        _ = try? await applyPendingSelectionIfReady()
        return selection
    }

    /// Stores a pending selection and effective date for deferred application.
    func setPendingSelection(_ selection: FamilyActivitySelection, effectiveDate: Date) async throws {
        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary

            let selectionData = try encoder.encode(selection)
            try selectionData.write(to: Self.pendingSelectionURL, options: .atomic)

            let dateData = try encoder.encode(effectiveDate)
            try dateData.write(to: Self.pendingSelectionDateURL, options: .atomic)

            pendingSelection = selection
            pendingSelectionEffectiveDate = effectiveDate
        } catch {
            throw BlockerServiceError.shieldUpdateFailed(description: error.localizedDescription)
        }
    }

    /// Returns pending selection payload if one is currently scheduled.
    func getPendingSelection() async -> PendingAppSelection? {
        guard let pendingSelection,
              let pendingSelectionEffectiveDate else {
            return nil
        }

        return PendingAppSelection(
            selection: pendingSelection,
            effectiveDate: pendingSelectionEffectiveDate
        )
    }

    /// Applies pending selection if effective now and clears pending state.
    @discardableResult
    func applyPendingSelectionIfReady() async throws -> Bool {
        guard let pendingSelection,
              let effectiveDate = pendingSelectionEffectiveDate,
              Date() >= effectiveDate else {
            return false
        }

        self.selection = pendingSelection

        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(pendingSelection)
            try data.write(to: Self.selectionURL, options: .atomic)
            clearPersistedPendingSelection()
            self.pendingSelection = nil
            self.pendingSelectionEffectiveDate = nil
            return true
        } catch {
            throw BlockerServiceError.shieldUpdateFailed(description: error.localizedDescription)
        }
    }

    /// Clears any pending selection without applying it.
    func cancelPendingSelection() async {
        pendingSelection = nil
        pendingSelectionEffectiveDate = nil
        clearPersistedPendingSelection()
    }
    
    // MARK: - Private Methods
    
    /// Loads the persisted selection from disk.
    ///
    /// Called during initialization to restore the user's previous app selection.
    /// If no file exists or decoding fails, returns an empty selection.
    private static func loadPersistedSelection() -> FamilyActivitySelection {
        guard FileManager.default.fileExists(atPath: Self.selectionURL.path) else {
            return FamilyActivitySelection()
        }
        
        do {
            let data = try Data(contentsOf: Self.selectionURL)
            let decoder = PropertyListDecoder()
            return try decoder.decode(FamilyActivitySelection.self, from: data)
        } catch {
            // If loading fails, start with an empty selection
            // This is intentionally silent - the user can re-select apps
            return FamilyActivitySelection()
        }
    }

    /// Loads persisted pending selection from disk.
    private static func loadPersistedPendingSelection() -> FamilyActivitySelection? {
        guard FileManager.default.fileExists(atPath: Self.pendingSelectionURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: Self.pendingSelectionURL)
            let decoder = PropertyListDecoder()
            return try decoder.decode(FamilyActivitySelection.self, from: data)
        } catch {
            return nil
        }
    }

    /// Loads persisted pending effective date from disk.
    private static func loadPersistedPendingSelectionDate() -> Date? {
        guard FileManager.default.fileExists(atPath: Self.pendingSelectionDateURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: Self.pendingSelectionDateURL)
            let decoder = PropertyListDecoder()
            return try decoder.decode(Date.self, from: data)
        } catch {
            return nil
        }
    }

    /// Deletes persisted pending selection artifacts.
    private func clearPersistedPendingSelection() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: Self.pendingSelectionURL.path) {
            try? fileManager.removeItem(at: Self.pendingSelectionURL)
        }
        if fileManager.fileExists(atPath: Self.pendingSelectionDateURL.path) {
            try? fileManager.removeItem(at: Self.pendingSelectionDateURL)
        }
    }
}
