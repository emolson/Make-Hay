//
//  DashboardViewModelPendingGoalTests.swift
//  Make HayTests
//
//  Tests that `schedulePendingGoal` correctly clears stale pending state
//  when a later edit reverts a goal back to its live value.
//

import Foundation
import Testing
@testable import Make_Hay

@MainActor
struct DashboardViewModelPendingGoalTests {

    /// Creates a DashboardViewModel with mocks, pre-configured with the given goal.
    private func makeSUT(goal: HealthGoal) -> DashboardViewModel {
        let vm = DashboardViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService(),
            timeUnlockScheduler: MockTimeUnlockScheduler()
        )
        vm.healthGoal = goal
        return vm
    }

    // MARK: - Step Goal Revert

    @Test("Reverting a deferred step goal edit clears pendingStepGoal")
    func revertDeferredStepGoalClearsPending() {
        var goal = HealthGoal()
        goal.stepGoal = StepGoal(isEnabled: true, target: 10_000)
        let sut = makeSUT(goal: goal)

        // First deferral: lower the target to 5,000
        var lowered = goal
        lowered.stepGoal.target = 5_000
        sut.schedulePendingGoal(lowered)
        #expect(sut.healthGoal.pendingStepGoal != nil)
        #expect(sut.healthGoal.pendingStepGoal?.target == 5_000)

        // Second deferral: revert back to 10,000 (matching the live model)
        sut.schedulePendingGoal(goal)
        #expect(sut.healthGoal.pendingStepGoal == nil,
                "Pending step goal should be cleared when reverted to live value")
    }

    // MARK: - Active Energy Goal Revert

    @Test("Reverting a deferred active energy edit clears pendingActiveEnergyGoal")
    func revertDeferredActiveEnergyGoalClearsPending() {
        var goal = HealthGoal()
        goal.activeEnergyGoal = ActiveEnergyGoal(isEnabled: true, target: 500)
        let sut = makeSUT(goal: goal)

        var lowered = goal
        lowered.activeEnergyGoal.target = 200
        sut.schedulePendingGoal(lowered)
        #expect(sut.healthGoal.pendingActiveEnergyGoal?.target == 200)

        sut.schedulePendingGoal(goal)
        #expect(sut.healthGoal.pendingActiveEnergyGoal == nil,
                "Pending active energy goal should be cleared when reverted to live value")
    }

    // MARK: - Time Block Goal Revert

    @Test("Reverting a deferred time block edit clears pendingTimeBlockGoal")
    func revertDeferredTimeBlockGoalClearsPending() {
        var goal = HealthGoal()
        goal.timeBlockGoal = TimeBlockGoal(isEnabled: true, unlockTimeMinutes: 19 * 60)
        let sut = makeSUT(goal: goal)

        var lowered = goal
        lowered.timeBlockGoal.unlockTimeMinutes = 12 * 60
        sut.schedulePendingGoal(lowered)
        #expect(sut.healthGoal.pendingTimeBlockGoal?.unlockTimeMinutes == 12 * 60)

        sut.schedulePendingGoal(goal)
        #expect(sut.healthGoal.pendingTimeBlockGoal == nil,
                "Pending time block goal should be cleared when reverted to live value")
    }

    // MARK: - Exercise Goal Edit Revert

    @Test("Reverting a deferred exercise goal edit clears the pending exercise entry")
    func revertDeferredExerciseGoalEditClearsPending() {
        let exerciseId = UUID()
        var goal = HealthGoal()
        goal.exerciseGoals = [
            ExerciseGoal(id: exerciseId, isEnabled: true, targetMinutes: 30)
        ]
        let sut = makeSUT(goal: goal)

        var edited = goal
        edited.exerciseGoals[0].targetMinutes = 10
        sut.schedulePendingGoal(edited)
        #expect(sut.healthGoal.pendingExerciseGoals.count == 1)
        #expect(sut.healthGoal.pendingExerciseGoals.first?.targetMinutes == 10)

        // Revert to original
        sut.schedulePendingGoal(goal)
        #expect(sut.healthGoal.pendingExerciseGoals.isEmpty,
                "Pending exercise edit should be cleared when reverted to live value")
    }

    // MARK: - Exercise Goal Deletion Revert

    @Test("Un-deleting a deferred exercise goal removal clears the deletion marker")
    func revertDeferredExerciseDeletionClearsMarker() {
        let exerciseId = UUID()
        var goal = HealthGoal()
        goal.exerciseGoals = [
            ExerciseGoal(id: exerciseId, isEnabled: true, targetMinutes: 30)
        ]
        let sut = makeSUT(goal: goal)

        // Propose deleting the exercise goal
        var deleted = goal
        deleted.exerciseGoals = []
        sut.schedulePendingGoal(deleted)
        #expect(sut.healthGoal.pendingExerciseGoalDeletions.contains(exerciseId))

        // Revert: goal is back in the proposal
        sut.schedulePendingGoal(goal)
        #expect(!sut.healthGoal.pendingExerciseGoalDeletions.contains(exerciseId),
                "Deletion marker should be removed when exercise goal is restored in proposal")
    }

    // MARK: - Effective Date Cleanup

    @Test("pendingGoalEffectiveDate is nil when all pending changes are reverted")
    func effectiveDateClearedWhenAllReverted() {
        var goal = HealthGoal()
        goal.stepGoal = StepGoal(isEnabled: true, target: 10_000)
        goal.activeEnergyGoal = ActiveEnergyGoal(isEnabled: true, target: 500)
        let sut = makeSUT(goal: goal)

        // Defer changes to both goals
        var lowered = goal
        lowered.stepGoal.target = 5_000
        lowered.activeEnergyGoal.target = 200
        sut.schedulePendingGoal(lowered)
        #expect(sut.healthGoal.pendingGoalEffectiveDate != nil)

        // Revert everything back
        sut.schedulePendingGoal(goal)
        #expect(sut.healthGoal.pendingGoalEffectiveDate == nil,
                "Effective date should be cleared when no pending changes remain")
        #expect(!sut.healthGoal.hasPendingChanges)
    }
}
