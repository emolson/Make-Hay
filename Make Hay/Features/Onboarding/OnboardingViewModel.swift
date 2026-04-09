//
//  OnboardingViewModel.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import FamilyControls
import Foundation
import os.log
import SwiftUI

/// Represents the steps in the onboarding flow.
///
/// Order: welcome → setupGoal → health → screenTime → chooseApps → success.
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case setupGoal = 1
    case health = 2
    case screenTime = 3
    case chooseApps = 4
    case success = 5
}

/// ViewModel managing the onboarding flow state and permission requests.
/// Uses @MainActor isolation to ensure all UI state updates happen on the main thread.
@Observable
@MainActor
final class OnboardingViewModel {
    // MARK: - State Properties
    
    /// The current step in the onboarding flow.
    var currentStep: OnboardingStep = .welcome
    
    /// Current HealthKit permission state.
    var healthAuthorizationStatus: HealthAuthorizationStatus = .notDetermined

    /// Whether HealthKit's one-time prompt has already been shown.
    var healthAuthorizationPromptShown: Bool = false

    /// Whether HealthKit permission has been granted.
    var healthPermissionGranted: Bool {
        healthAuthorizationStatus.isAuthorized
    }
    
    /// Whether Screen Time permission has been granted.
    var screenTimePermissionGranted: Bool = false
    
    /// Whether the user's selected goal requires HealthKit data.
    /// Derived from `selectedGoalType`: only Time Unlock goals skip Health.
    var selectedGoalRequiresHealth: Bool {
        guard let type = selectedGoalType else { return true }
        return type != .timeUnlock
    }
    
    /// Whether a permission request is currently in progress.
    var isRequestingPermission: Bool = false
    
    /// Error message to display if a permission request fails.
    var errorMessage: String?
    
    /// Whether the user has denied the Screen Time system prompt.
    ///
    /// **Why a separate flag?** `errorMessage` can be dismissed by the user, but the
    /// denial state should persist so the "Open Settings" recovery path remains visible
    /// even after the error banner is dismissed.
    var screenTimeDenied: Bool = false
    
    // MARK: - Goal Configuration State
    
    /// The goal type the user selected during the setupGoal step.
    var selectedGoalType: GoalType?
    
    /// The target value for the selected goal (steps, kcal, minutes, or time-unlock minutes).
    var goalTarget: Double = 8_000
    
    /// The exercise type filter (only used for exercise goals).
    var selectedExerciseType: ExerciseType = .any
    
    /// The repeat schedule day selection. Defaults to all days ("Every day").
    var selectedDays: Set<Weekday> = Set(Weekday.allCases)
    
    /// The unlock time for time-unlock goals. Defaults to 7 PM.
    var unlockTime: Date = {
        var components = DateComponents()
        components.hour = 19
        components.minute = 0
        return Calendar.current.date(from: components) ?? Date()
    }()
    
    // MARK: - App Picker State
    
    /// Controls presentation of the `FamilyActivityPicker` during the chooseApps step.
    var isAppPickerPresented: Bool = false
    
    /// Live binding given to `FamilyActivityPicker`. Persisted on picker dismissal.
    var appDraftSelection: FamilyActivitySelection = FamilyActivitySelection()
    
    /// Whether a save/shield update is in-flight after picker dismissal.
    private(set) var isSavingAppSelection: Bool = false
    
    /// Number of individual apps currently selected.
    var selectedAppCount: Int {
        appDraftSelection.applicationTokens.count
    }
    
    /// Number of categories currently selected.
    var selectedCategoryCount: Int {
        appDraftSelection.categoryTokens.count
    }
    
    /// Whether any apps or categories have been selected.
    var hasSelectedApps: Bool {
        selectedAppCount > 0 || selectedCategoryCount > 0
    }
    
    /// Whether the user has interacted with the picker at least once (to distinguish
    /// "never opened" from "opened and dismissed with nothing").
    private(set) var hasOpenedAppPicker: Bool = false
    
    /// Whether the user has fully configured a goal (type selected + valid target).
    var isGoalConfigured: Bool {
        guard let type = selectedGoalType else { return false }
        switch type {
        case .steps:
            return goalTarget >= 1_000 && goalTarget <= 50_000
        case .activeEnergy:
            return goalTarget >= 50 && goalTarget <= 2_000
        case .exercise:
            return goalTarget >= 5 && goalTarget <= 180
        case .timeUnlock:
            return true
        }
    }

    /// Whether health permission was required by the selected goal but was not granted.
    ///
    /// Used on the success screen to surface a "connect anytime" recovery hint when the
    /// user skipped or denied HealthKit during onboarding.
    var healthWasSkipped: Bool {
        selectedGoalRequiresHealth && !healthPermissionGranted
    }

    /// The ordered list of onboarding steps that will be shown to the user in the current state.
    ///
    /// Filters out steps where `shouldSkip` returns `true` so the progress bar denominator
    /// reflects only the steps the user will actually see — no inflation from auto-skipped gates.
    private var visibleSteps: [OnboardingStep] {
        OnboardingStep.allCases.filter { !shouldSkip($0) }
    }

    /// Progress through the visible onboarding steps expressed as a value from 0.0 to 1.0.
    ///
    /// Accounts for conditional steps (e.g. health skipped for Time Unlock goals) so the
    /// indicator always communicates real forward momentum without a fixed-count ceiling.
    var stepProgress: Double {
        let visible = visibleSteps
        guard let index = visible.firstIndex(of: currentStep) else { return 0 }
        let total = visible.count
        guard total > 1 else { return 1 }
        return Double(index) / Double(total - 1)
    }

    /// Human-readable summary of the configured goal.
    /// e.g. "Walk 10,000 steps every day" or "30 minutes of exercise on Weekdays".
    var goalSummaryText: String {
        guard let type = selectedGoalType else { return "" }
        let schedule = GoalSchedule.from(weekdays: selectedDays)
        let scheduleSuffix = schedule.displaySummary.lowercased()
        
        switch type {
        case .steps:
            let formatted = Int(goalTarget).formatted()
            return String(localized: "Walk \(formatted) steps \(scheduleSuffix)")
        case .activeEnergy:
            let formatted = Int(goalTarget).formatted()
            return String(localized: "Burn \(formatted) active calories \(scheduleSuffix)")
        case .exercise:
            let formatted = Int(goalTarget)
            return String(localized: "\(formatted) minutes of exercise \(scheduleSuffix)")
        case .timeUnlock:
            let timeString = Self.timeFormatter.string(from: unlockTime)
            return String(localized: "Unlock at \(timeString) \(scheduleSuffix)")
        }
    }
    
    // MARK: - Cached Formatters

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Dependencies
    
    /// The health service for HealthKit operations.
    private let healthService: any HealthServiceProtocol
    
    /// The blocker service for Screen Time/FamilyControls operations.
    private let blockerService: any BlockerServiceProtocol

    private static let logger = AppLogger.logger(category: "OnboardingViewModel")
    
    // MARK: - Initialization
    
    /// Creates a new OnboardingViewModel with the specified services.
    /// - Parameters:
    ///   - healthService: The service to use for health data operations.
    ///   - blockerService: The service to use for app blocking operations.
    init(
        healthService: any HealthServiceProtocol,
        blockerService: any BlockerServiceProtocol
    ) {
        self.healthService = healthService
        self.blockerService = blockerService

        let seededPromptShown = SharedStorage.healthAuthorizationPromptShown
            || SharedStorage.healthPermissionGranted
        let seededHealthStatus: HealthAuthorizationStatus = SharedStorage.healthPermissionGranted
            ? .authorized
            : .notDetermined

        self.healthAuthorizationStatus = seededHealthStatus.normalized(promptShown: seededPromptShown)
        self.healthAuthorizationPromptShown = seededPromptShown
        self.screenTimePermissionGranted = SharedStorage.screenTimePermissionGranted
    }
    
    // MARK: - Navigation
    
    /// Advances to the next applicable onboarding step, auto-skipping steps whose
    /// preconditions are already satisfied (e.g., permissions already granted).
    func advanceToNextStep() {
        var candidate = OnboardingStep(rawValue: currentStep.rawValue + 1)
        while let step = candidate, shouldSkip(step) {
            candidate = OnboardingStep(rawValue: step.rawValue + 1)
        }
        guard let next = candidate else { return }
        withAnimation(.easeInOut) {
            currentStep = next
        }
    }

    /// Whether the given step should be auto-skipped in the current state.
    private func shouldSkip(_ step: OnboardingStep) -> Bool {
        switch step {
        case .health:
            return healthPermissionGranted
        case .screenTime:
            return screenTimePermissionGranted
        default:
            return false
        }
    }
    
    // MARK: - Goal Configuration
    
    /// Sets the selected goal type and pre-fills defaults matching the existing
    /// `GoalConfigurationView` initialization logic.
    func configureGoal(type: GoalType) {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedGoalType = type
        }
        selectedDays = Set(Weekday.allCases)
        
        switch type {
        case .steps:
            goalTarget = 8_000
        case .activeEnergy:
            goalTarget = 500
        case .exercise:
            goalTarget = 30
            selectedExerciseType = .any
        case .timeUnlock:
            goalTarget = Double(19 * 60)
            var components = DateComponents()
            components.hour = 19
            components.minute = 0
            unlockTime = Calendar.current.date(from: components) ?? Date()
        }
    }
    
    /// Resets goal type selection so the user can pick a different type.
    func resetGoalSelection() {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedGoalType = nil
        }
    }

    /// Syncs `goalTarget` from the current `unlockTime` value.
    /// Called by the View's `.onChange(of: unlockTime)` to keep time-picker
    /// changes reflected in the goal target without inline Calendar math in the View.
    func syncUnlockTimeToGoalTarget() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: unlockTime)
        goalTarget = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
    }
    
    /// Persists the configured goal to `HealthGoal` storage.
    ///
    /// **Why persist directly instead of using `DashboardViewModel`?** Onboarding
    /// runs before the Dashboard is visible. The Dashboard reloads from
    /// `HealthGoal.load()` on appear, so direct persistence keeps the dependency
    /// graph clean.
    func saveOnboardingGoal() {
        guard let type = selectedGoalType else { return }
        
        let schedule = GoalSchedule.from(weekdays: selectedDays)
        var goal = HealthGoal()
        
        switch type {
        case .steps:
            goal.stepGoal.isEnabled = true
            goal.stepGoal.target = Int(goalTarget)
            goal.stepGoal.schedule = schedule
        case .activeEnergy:
            goal.activeEnergyGoal.isEnabled = true
            goal.activeEnergyGoal.target = Int(goalTarget)
            goal.activeEnergyGoal.schedule = schedule
        case .exercise:
            let exerciseGoal = ExerciseGoal(
                isEnabled: true,
                targetMinutes: Int(goalTarget),
                exerciseType: selectedExerciseType,
                schedule: schedule
            )
            goal.exerciseGoals.append(exerciseGoal)
        case .timeUnlock:
            goal.timeBlockGoal.isEnabled = true
            goal.timeBlockGoal.unlockTimeMinutes = Int(goalTarget)
            goal.timeBlockGoal.schedule = schedule
        }
        
        HealthGoal.save(goal)
    }

    /// Refreshes permission state from the live services.
    ///
    /// **Why refresh on launch?** If the user already granted a permission in an earlier
    /// session, onboarding should immediately reflect that state instead of briefly showing
    /// the unchecked version of the step.
    func refreshPermissionState() async {
        await syncLiveHealthAuthorizationState()
        let latestScreenTimeStatus = await blockerService.isAuthorized

        screenTimePermissionGranted = latestScreenTimeStatus
        SharedStorage.screenTimePermissionGranted = screenTimePermissionGranted
    }

    @discardableResult
    private func syncLiveHealthAuthorizationState() async -> HealthAuthorizationStatus {
        let promptShown = await healthService.authorizationPromptShown
        let status = (await healthService.authorizationStatus).normalized(promptShown: promptShown)

        healthAuthorizationStatus = status
        healthAuthorizationPromptShown = promptShown || status.promptHasBeenShown
        SharedStorage.healthPermissionGranted = status.isAuthorized
        SharedStorage.healthAuthorizationPromptShown = healthAuthorizationPromptShown

        return status
    }
    
    // MARK: - Permission Requests
    
    /// Requests HealthKit authorization.
    /// Updates `healthPermissionGranted` based on the live authorization status after the
    /// request completes, rather than assuming success means the user granted access.
    ///
    /// **Why check live status?** Apple's `requestAuthorization()` does not throw when the
    /// user dismisses the prompt without granting access. The only way to determine
    /// the actual outcome is to query the service's `authorizationStatus` afterward.
    func requestHealthPermission() async {
        errorMessage = nil
        isRequestingPermission = true
        await syncLiveHealthAuthorizationState()

        guard healthAuthorizationStatus == .notDetermined,
              !healthAuthorizationPromptShown else {
            isRequestingPermission = false
            return
        }
        
        do {
            try await healthService.requestAuthorization()
            await syncLiveHealthAuthorizationState()
        } catch let error as HealthServiceError {
            let recoveredStatus = await syncLiveHealthAuthorizationState()
            errorMessage = recoveredStatus == .notDetermined && !healthAuthorizationPromptShown
                ? error.errorDescription
                : nil
        } catch {
            let recoveredStatus = await syncLiveHealthAuthorizationState()
            errorMessage = recoveredStatus == .notDetermined && !healthAuthorizationPromptShown
                ? error.localizedDescription
                : nil
        }
        
        isRequestingPermission = false
    }
    
    /// Requests Screen Time (FamilyControls) authorization.
    /// Updates `screenTimePermissionGranted` on success or `errorMessage` on failure.
    func requestScreenTimePermission() async {
        errorMessage = nil
        isRequestingPermission = true
        
        do {
            try await blockerService.requestAuthorization()
            screenTimePermissionGranted = true
            screenTimeDenied = false
            SharedStorage.screenTimePermissionGranted = true
        } catch let error as BlockerServiceError {
            errorMessage = error.errorDescription
            screenTimePermissionGranted = false
            screenTimeDenied = true
            SharedStorage.screenTimePermissionGranted = false
        } catch {
            errorMessage = error.localizedDescription
            screenTimePermissionGranted = false
            screenTimeDenied = true
            SharedStorage.screenTimePermissionGranted = false
        }
        
        isRequestingPermission = false
    }
    
    /// Clears any displayed error message.
    func dismissError() {
        errorMessage = nil
    }
    
    // MARK: - App Picker
    
    /// Presents the `FamilyActivityPicker`.
    func presentAppPicker() {
        isAppPickerPresented = true
        hasOpenedAppPicker = true
    }
    
    /// Called when `isAppPickerPresented` transitions from `true` → `false`.
    ///
    /// Persists `appDraftSelection` to the same `FamilyActivitySelection` storage used
    /// by the rest of the app, then applies shields. During onboarding the user has no
    /// existing selection to guard, so no deferral logic is needed.
    func appPickerDismissed() {
        Task {
            await persistAppSelection()
        }
    }
    
    /// Persists the draft app selection and synchronises shields.
    private func persistAppSelection() async {
        let selection = appDraftSelection
        let hasApps = !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        
        isSavingAppSelection = true
        defer { isSavingAppSelection = false }
        
        do {
            try await blockerService.setSelection(selection)
        } catch {
            let _ = error
            Self.logger.warning("Onboarding app selection save failed.")
            errorMessage = String(localized: "Could not save your app selection. Please try again.")
            return
        }

        do {
            try await blockerService.updateShields(shouldBlock: hasApps)
        } catch {
            // Non-fatal during onboarding — the selection is persisted, so the
            // user can fix blocking in Settings later.
            let _ = error
            Self.logger.warning("Onboarding shield update failed.")
            errorMessage = String(localized: "App selection saved, but blocking could not be applied. You can fix this in Settings.")
        }
    }
}

