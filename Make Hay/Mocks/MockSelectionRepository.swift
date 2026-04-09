//
//  MockSelectionRepository.swift
//  Make Hay
//
//  Created by GitHub Copilot on 4/9/26.
//

import FamilyControls
import Foundation

/// In-memory mock of `SelectionRepositoryProtocol` for previews and unit tests.
///
/// All state is held in memory — no disk I/O, no App Group, no entitlements required.
struct MockSelectionRepository: SelectionRepositoryProtocol, Sendable {
    func loadSelection() -> FamilyActivitySelection { FamilyActivitySelection() }
    func saveSelection(_ selection: FamilyActivitySelection) throws {}
    func loadPendingSelection() -> FamilyActivitySelection? { nil }
    func loadPendingSelectionDate() -> Date? { nil }
    func savePendingSelection(_ selection: FamilyActivitySelection, effectiveDate: Date) throws {}
    func clearPendingSelection() {}
}
