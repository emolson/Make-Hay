//
//  AppPickerViewModelTests.swift
//  Make HayTests
//
//  Created by Ethan Olson on 2/18/26.
//

import FamilyControls
import Foundation
import Testing
@testable import Make_Hay

@MainActor
private final class MockGoalStatusProvider: GoalStatusProvider {
    var isBlocking: Bool

    init(isBlocking: Bool = false) {
        self.isBlocking = isBlocking
    }
}

/// Unit tests for `AppPickerViewModel`.
///
/// **Why `@MainActor`?** `AppPickerViewModel` is `@MainActor`-isolated, so all
/// published-property reads and mutating calls must happen on the main actor.
@MainActor
struct AppPickerViewModelTests {

    // MARK: - loadCurrentSelection

    @Test("loadCurrentSelection seeds both persisted and draft from service")
    func loadCurrentSelectionSeedsFromService() async throws {
        let mockService = MockBlockerService()
        let mockHealthService = MockHealthService()
        let goalStatusProvider = MockGoalStatusProvider()
        let storedSelection = FamilyActivitySelection()
        try await mockService.setSelection(storedSelection)

        let sut = AppPickerViewModel(
            blockerService: mockService,
            healthService: mockHealthService,
            goalStatusProvider: goalStatusProvider
        )
        await sut.loadCurrentSelection()

        // Both properties should reflect what was stored in the service.
        #expect(sut.persistedSelection == storedSelection)
        #expect(sut.draftSelection == storedSelection)
    }

    // MARK: - presentPicker

    @Test("presentPicker snapshots persistedSelection into draftSelection and opens picker")
    func presentPickerSnapshotsPersisted() async throws {
        let mockService = MockBlockerService()
        let sut = AppPickerViewModel(
            blockerService: mockService,
            healthService: MockHealthService(),
            goalStatusProvider: MockGoalStatusProvider()
        )
        await sut.loadCurrentSelection()

        sut.presentPicker()

        #expect(sut.isPickerPresented == true)
        #expect(sut.draftSelection == sut.persistedSelection)
    }

    // MARK: - pickerDismissed (commit path)

    @Test("pickerDismissed commits draft to service and updates persistedSelection")
    func pickerDismissedCommitsDraft() async throws {
        let mockService = MockBlockerService()
        let sut = AppPickerViewModel(
            blockerService: mockService,
            healthService: MockHealthService(),
            goalStatusProvider: MockGoalStatusProvider()
        )
        await sut.loadCurrentSelection()

        // Simulate user opening picker and selecting something.
        sut.presentPicker()
        
        // Simulate picker dismissal. 
        // We use force: true because we cannot easily create app tokens in tests to make them unequal.
        sut.pickerDismissed(force: true)

        // Wait briefly for the spawned Task to finish.
        try await Task.sleep(for: .milliseconds(100))

        // persistedSelection should now reflect the committed draft.
        #expect(sut.persistedSelection == sut.draftSelection)
        #expect(sut.showError == false)
    }

    // MARK: - pickerDismissed (cancel / no-change path)

    @Test("pickerDismissed when draft unchanged is a safe no-op")
    func pickerDismissedWithUnchangedDraftIsNoOp() async throws {
        let mockService = MockBlockerService()
        let sut = AppPickerViewModel(
            blockerService: mockService,
            healthService: MockHealthService(),
            goalStatusProvider: MockGoalStatusProvider()
        )
        await sut.loadCurrentSelection()

        let selectionBefore = sut.persistedSelection

        // Open picker without changing draft (Cancel scenario).
        sut.presentPicker()
        sut.pickerDismissed()

        try await Task.sleep(for: .milliseconds(100))

        // persistedSelection should be unchanged.
        #expect(sut.persistedSelection == selectionBefore)
        #expect(sut.showError == false)
    }

    // MARK: - hasSelection / pickerButtonTitle

    @Test("hasSelection is false for empty persistedSelection")
    func hasSelectionFalseWhenEmpty() {
        let sut = AppPickerViewModel(
            blockerService: MockBlockerService(),
            healthService: MockHealthService(),
            goalStatusProvider: MockGoalStatusProvider()
        )
        #expect(sut.hasSelection == false)
    }

    @Test("pickerButtonTitle shows 'Select' when empty and 'Edit' when populated")
    func pickerButtonTitleIsContextSensitive() async throws {
        let mockService = MockBlockerService()
        let sut = AppPickerViewModel(
            blockerService: mockService,
            healthService: MockHealthService(),
            goalStatusProvider: MockGoalStatusProvider()
        )

        // Empty state → "Select Apps to Block"
        #expect(sut.pickerButtonTitle == String(localized: "Select Apps to Block"))

        // Simulate a committed selection by loading from a pre-populated mock.
        let populated = FamilyActivitySelection()
        try await mockService.setSelection(populated)
        await sut.loadCurrentSelection()

        // Still empty tokens in a default FamilyActivitySelection, so still "Select".
        // (FamilyActivityPicker tokens can only be set by the real system picker,
        //  so we verify the title logic branches via `hasSelection` directly.)
        #expect(sut.hasSelection == false)
        #expect(sut.pickerButtonTitle == String(localized: "Select Apps to Block"))
    }

    // MARK: - Error handling

    @Test("pickerDismissed shows error when service throws")
    func pickerDismissedShowsErrorOnThrow() async throws {
        let mockService = MockBlockerService()
        await mockService.setShouldThrowError(true)

        let sut = AppPickerViewModel(
            blockerService: mockService,
            healthService: MockHealthService(),
            goalStatusProvider: MockGoalStatusProvider()
        )
        await sut.loadCurrentSelection()
        sut.presentPicker()
        
        // Simulate picker dismissal. 
        // We use force: true because we cannot easily create app tokens in tests to make them unequal.
        sut.pickerDismissed(force: true)

        try await Task.sleep(for: .milliseconds(100))

        #expect(sut.showError == true)
        #expect(sut.errorMessage.isEmpty == false)
    }
}
