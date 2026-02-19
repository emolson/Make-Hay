//
//  AppPickerViewModel.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/18/26.
//

import FamilyControls
import Combine
import UIKit

/// ViewModel managing the full lifecycle of the blocked-app picker session.
///
/// **Why extract to a ViewModel?**
/// The previous `AppPickerView` called persistence, shield updates, and haptic
/// feedback directly — all business logic that belongs here per MVVM guidelines.
///
/// **Why two selection properties?**
/// `FamilyActivityPicker` updates its binding live as the user navigates the picker.
/// By binding the picker to `draftSelection` (seeded from `persistedSelection` on
/// open) and only writing to the service on picker *dismissal*, we prevent transient
/// empty-state mutations from overwriting a valid saved selection.
@MainActor
final class AppPickerViewModel: ObservableObject {

    // MARK: - Published State

    /// Live binding given to `FamilyActivityPicker`.
    /// Seeded from `persistedSelection` when the picker opens.
    @Published var draftSelection: FamilyActivitySelection = FamilyActivitySelection()

    /// The last successfully committed selection — drives the summary UI.
    @Published private(set) var persistedSelection: FamilyActivitySelection = FamilyActivitySelection()

    /// Controls picker sheet presentation.
    @Published var isPickerPresented: Bool = false

    /// `true` while a save/shield update is in-flight.
    @Published private(set) var isSaving: Bool = false

    /// Whether an error alert should be shown.
    @Published var showError: Bool = false

    /// Error description forwarded to the alert message.
    @Published private(set) var errorMessage: String = ""

    // MARK: - Computed Properties

    /// Whether any apps or categories are currently committed as blocked.
    var hasSelection: Bool {
        !persistedSelection.applicationTokens.isEmpty || !persistedSelection.categoryTokens.isEmpty
    }

    /// Context-sensitive picker button title: "Select Apps" when empty, "Edit" when populated.
    var pickerButtonTitle: String {
        hasSelection
            ? String(localized: "Edit Blocked Apps")
            : String(localized: "Select Apps to Block")
    }

    /// Context-sensitive SF Symbol for the picker button.
    var pickerButtonIcon: String {
        hasSelection ? "pencil.circle" : "plus.app"
    }

    // MARK: - Dependencies

    private let blockerService: any BlockerServiceProtocol

    // MARK: - Initialization

    /// - Parameter blockerService: Injected service for persisting selections and managing shields.
    init(blockerService: any BlockerServiceProtocol) {
        self.blockerService = blockerService
    }

    // MARK: - Intent Methods

    /// Loads the committed selection from the service.
    /// Called once from the view's `.task` modifier on first appear.
    func loadCurrentSelection() async {
        persistedSelection = await blockerService.getSelection()
        draftSelection = persistedSelection
    }

    /// Seeds `draftSelection` with the current committed selection, then presents the picker.
    ///
    /// **Why snapshot here?** Ensures the picker opens pre-populated with existing
    /// selections rather than an empty sheet, so editing feels natural.
    func presentPicker() {
        draftSelection = persistedSelection
        isPickerPresented = true
    }

    /// Called when `isPickerPresented` transitions from `true` → `false`.
    ///
    /// Commits `draftSelection` to the service. If the user tapped Cancel,
    /// `FamilyActivityPicker` does not update the binding — `draftSelection`
    /// stays equal to `persistedSelection` and the write is a data-level no-op.
    func pickerDismissed() {
        Task { await persistSelection(draftSelection) }
    }

    // MARK: - Private Methods

    /// Persists the given selection and synchronises shields.
    ///
    /// **Why update shields immediately?** The user expects the change to take effect
    /// right away; delaying until the next goal evaluation would be confusing.
    private func persistSelection(_ selection: FamilyActivitySelection) async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await blockerService.setSelection(selection)
            let hasApps = !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
            try await blockerService.updateShields(shouldBlock: hasApps)

            persistedSelection = selection
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
