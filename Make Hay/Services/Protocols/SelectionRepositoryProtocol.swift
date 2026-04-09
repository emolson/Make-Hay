//
//  SelectionRepositoryProtocol.swift
//  Make Hay
//
//  Created by GitHub Copilot on 4/9/26.
//

import FamilyControls
import Foundation

/// Protocol for persisting and loading `FamilyActivitySelection` payloads.
///
/// **Why a dedicated repository?** Extracting persistence out of `BlockerService`
/// gives the blocking actor a single write path with enforced file-protection policy,
/// explicit corruption recovery, and a testable seam for unit tests that don't need
/// a real App Group container on disk.
protocol SelectionRepositoryProtocol: Sendable {
    /// Loads the persisted active selection.
    ///
    /// Returns an empty `FamilyActivitySelection` when no file exists or the file
    /// is unreadable (corruption / migration). Callers should treat this as "no apps
    /// selected" rather than an error.
    func loadSelection() -> FamilyActivitySelection

    /// Atomically saves the active selection with file protection.
    /// - Throws: If encoding or the protected write fails.
    func saveSelection(_ selection: FamilyActivitySelection) throws

    /// Loads the persisted pending selection, if any.
    func loadPendingSelection() -> FamilyActivitySelection?

    /// Loads the persisted pending selection effective date, if any.
    func loadPendingSelectionDate() -> Date?

    /// Atomically saves the pending selection and its effective date with file protection.
    /// - Throws: If encoding or the protected write fails.
    func savePendingSelection(_ selection: FamilyActivitySelection, effectiveDate: Date) throws

    /// Deletes any persisted pending-selection artifacts.
    func clearPendingSelection()
}
