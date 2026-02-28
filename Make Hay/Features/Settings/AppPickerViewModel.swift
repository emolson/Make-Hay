//
//  AppPickerViewModel.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/18/26.
//

import FamilyControls
import HealthKit
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
@Observable
final class AppPickerViewModel {

    // MARK: - State

    /// Live binding given to `FamilyActivityPicker`.
    /// Seeded from `persistedSelection` when the picker opens.
    var draftSelection: FamilyActivitySelection = FamilyActivitySelection()

    /// The last successfully committed selection — drives the summary UI.
    private(set) var persistedSelection: FamilyActivitySelection = FamilyActivitySelection()

    /// Controls picker sheet presentation.
    var isPickerPresented: Bool = false

    /// `true` while a save/shield update is in-flight.
    private(set) var isSaving: Bool = false

    /// Whether an error alert should be shown.
    var showError: Bool = false

    /// Error description forwarded to the alert message.
    private(set) var errorMessage: String = ""

    /// Whether the next-day confirmation guard sheet should be shown.
    var showingPendingConfirmation: Bool = false

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
    private let healthService: any HealthServiceProtocol
    private let goalStatusProvider: any GoalStatusProvider

    /// Selection currently awaiting user confirmation for schedule/emergency paths.
    private var pendingSelectionCandidate: FamilyActivitySelection?
    
    /// Reference to the in-flight picker-dismissed task.
    ///
    /// **Why store this?** `pickerDismissed()` spawns an unstructured Task that can
    /// outlive the view. If the user re-opens the picker before the previous task
    /// completes, the old task could apply stale shields. Storing the reference
    /// allows us to cancel it before spawning a new one.
    private var dismissTask: Task<Void, Never>?

    // MARK: - Initialization

    /// - Parameters:
    ///   - blockerService: Injected service for persisting selections and managing shields.
    ///   - healthService: Injected service for fresh health reads before gate decisions.
    ///   - goalStatusProvider: Shared dashboard-backed provider for gate state continuity.
    init(
        blockerService: any BlockerServiceProtocol,
        healthService: any HealthServiceProtocol,
        goalStatusProvider: any GoalStatusProvider
    ) {
        self.blockerService = blockerService
        self.healthService = healthService
        self.goalStatusProvider = goalStatusProvider
    }

    // MARK: - Intent Methods

    /// Loads the committed selection from the service.
    /// Called once from the view's `.task` modifier on first appear.
    func loadCurrentSelection() async {
        _ = try? await blockerService.applyPendingSelectionIfReady()
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
    ///
    /// - Parameter force: If `true`, bypasses the equality check (used for testing).
    func pickerDismissed(force: Bool = false) {
        dismissTask?.cancel()
        dismissTask = Task {
            await handlePickerDismissed(with: draftSelection, force: force)
        }
    }

    /// Schedules the pending selection to apply at local midnight tomorrow.
    func schedulePendingSelection() async {
        guard let pendingSelectionCandidate else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await blockerService.setPendingSelection(
                pendingSelectionCandidate,
                effectiveDate: Date.localMidnightTomorrow()
            )
            self.pendingSelectionCandidate = nil
            showingPendingConfirmation = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    /// Applies the pending selection immediately, bypassing next-day deferral.
    func applyEmergencySelectionChange() async {
        guard let pendingSelectionCandidate else { return }

        self.pendingSelectionCandidate = nil
        showingPendingConfirmation = false
        await persistSelection(pendingSelectionCandidate)
    }

    // MARK: - Private Methods

    /// Handles picker dismissal by deciding between immediate persist and deferred guard flow.
    ///
    /// **Policy:** Adding new apps/categories to the block list is always allowed immediately
    /// because it makes the restriction *stricter*. Removing apps/categories loosens the
    /// restriction (an "easier" change), so it is gated behind the goal guard.
    private func handlePickerDismissed(with selection: FamilyActivitySelection, force: Bool = false) async {
        // Cancel/no-change path remains a data-level no-op.
        if !force {
            guard selection != persistedSelection else { return }
        }

        let isRemovingApps = !persistedSelection.applicationTokens.isSubset(of: selection.applicationTokens)
        let isRemovingCategories = !persistedSelection.categoryTokens.isSubset(of: selection.categoryTokens)
        let isWeakeningBlock = isRemovingApps || isRemovingCategories

        if isWeakeningBlock {
            let shouldDefer = await shouldDeferEdit()
            if shouldDefer {
                pendingSelectionCandidate = selection
                showingPendingConfirmation = true
                return
            }
        }

        await persistSelection(selection)
    }

    /// Returns true when edits must be deferred behind the next-day guard.
    ///
    /// **Policy:** Always prefer fresh health reads for gate decisions. If fresh
    /// fetch fails, default to deferred mode to avoid accidental bypass.
    ///
    /// **Why `WeeklyGoalSchedule` instead of `HealthGoal.load()`?** The legacy single-goal
    /// key is only synced on `WeeklyGoalSchedule.save()`. After midnight with no user
    /// interaction, the legacy key holds yesterday's config, causing wrong gate decisions.
    private func shouldDeferEdit() async -> Bool {
        let latestGoal = WeeklyGoalSchedule.load().todayGoal()
        return await GoalGatekeeper.shouldDeferEdits(
            goal: latestGoal,
            healthService: healthService
        )
    }

    /// Persists the given selection and synchronises shields.
    ///
    /// **Why check goal status before shielding?** The user may have already met their
    /// goals (apps unblocked). Blindly calling `updateShields(shouldBlock: true)` when
    /// apps are selected would re-lock them even though the user earned the unlock.
    /// We consult `goalStatusProvider.isBlocking` to preserve the current gate state.
    private func persistSelection(_ selection: FamilyActivitySelection) async {
        isSaving = true
        defer { isSaving = false }

        do {
            await blockerService.cancelPendingSelection()
            try await blockerService.setSelection(selection)
            let hasApps = !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
            // Only block if apps are selected AND the user hasn't already met their goals.
            let shouldBlock = hasApps && goalStatusProvider.isBlocking
            try await blockerService.updateShields(shouldBlock: shouldBlock)

            persistedSelection = selection
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

