//
//  OnboardingViewModelTests.swift
//  Make HayTests
//
//  Created by GitHub Copilot on 3/9/26.
//

import Foundation
import Testing
@testable import Make_Hay

@MainActor
struct OnboardingViewModelTests {

    @Test("refreshPermissionState syncs live authorization state")
    func refreshPermissionStateSyncsLiveAuthorizationState() async {
        let originalHealth = SharedStorage.healthPermissionGranted
        let originalHealthPromptShown = SharedStorage.healthAuthorizationPromptShown
        let originalScreenTime = SharedStorage.screenTimePermissionGranted
        defer {
            SharedStorage.healthPermissionGranted = originalHealth
            SharedStorage.healthAuthorizationPromptShown = originalHealthPromptShown
            SharedStorage.screenTimePermissionGranted = originalScreenTime
        }

        let healthService = MockHealthService()
        let blockerService = MockBlockerService()
        await healthService.setMockAuthorizationStatus(.authorized)
        await blockerService.setMockIsAuthorized(false)

        let sut = OnboardingViewModel(
            healthService: healthService,
            blockerService: blockerService
        )

        await sut.refreshPermissionState()

        #expect(sut.healthPermissionGranted == true)
        #expect(sut.healthAuthorizationStatus == .authorized)
        #expect(sut.screenTimePermissionGranted == false)
        #expect(SharedStorage.healthPermissionGranted == true)
        #expect(SharedStorage.healthAuthorizationPromptShown == true)
        #expect(SharedStorage.screenTimePermissionGranted == false)
    }

    @Test("requestHealthPermission marks Health as granted on success")
    func requestHealthPermissionMarksGrantedOnSuccess() async {
        let originalHealth = SharedStorage.healthPermissionGranted
        let originalHealthPromptShown = SharedStorage.healthAuthorizationPromptShown
        defer {
            SharedStorage.healthPermissionGranted = originalHealth
            SharedStorage.healthAuthorizationPromptShown = originalHealthPromptShown
        }

        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )

        await sut.requestHealthPermission()

        #expect(sut.healthPermissionGranted == true)
        #expect(sut.healthAuthorizationStatus == .authorized)
        #expect(sut.errorMessage == nil)
        #expect(SharedStorage.healthPermissionGranted == true)
        #expect(SharedStorage.healthAuthorizationPromptShown == true)
    }

    @Test("requestHealthPermission shows an error on failure")
    func requestHealthPermissionShowsErrorOnFailure() async {
        let originalHealth = SharedStorage.healthPermissionGranted
        let originalHealthPromptShown = SharedStorage.healthAuthorizationPromptShown
        defer {
            SharedStorage.healthPermissionGranted = originalHealth
            SharedStorage.healthAuthorizationPromptShown = originalHealthPromptShown
        }

        let healthService = MockHealthService()
        await healthService.setMockAuthorizationStatus(.notDetermined)
        await healthService.setShouldThrowError(true)

        let sut = OnboardingViewModel(
            healthService: healthService,
            blockerService: MockBlockerService()
        )

        await sut.requestHealthPermission()

        #expect(sut.healthPermissionGranted == false)
        #expect(sut.healthAuthorizationStatus == .notDetermined)
        #expect(sut.errorMessage?.isEmpty == false)
        #expect(SharedStorage.healthPermissionGranted == false)
    }

    @Test("requestHealthPermission recovers when HealthKit times out after consuming the prompt")
    func requestHealthPermissionRecoversAfterPromptWasConsumed() async {
        let originalHealth = SharedStorage.healthPermissionGranted
        let originalHealthPromptShown = SharedStorage.healthAuthorizationPromptShown
        defer {
            SharedStorage.healthPermissionGranted = originalHealth
            SharedStorage.healthAuthorizationPromptShown = originalHealthPromptShown
        }

        let healthService = MockHealthService()
        await healthService.setMockAuthorizationStatus(.notDetermined)
        await healthService.setMockAuthorizationPromptShown(false)
        await healthService.setMockAuthorizationOutcomeAfterRequest(
            status: .authorized,
            promptShown: true
        )
        await healthService.setShouldThrowError(true)

        let sut = OnboardingViewModel(
            healthService: healthService,
            blockerService: MockBlockerService()
        )

        await sut.requestHealthPermission()

        #expect(sut.healthPermissionGranted == true)
        #expect(sut.healthAuthorizationStatus == .authorized)
        #expect(sut.healthAuthorizationPromptShown == true)
        #expect(sut.errorMessage == nil)
        #expect(SharedStorage.healthPermissionGranted == true)
        #expect(SharedStorage.healthAuthorizationPromptShown == true)
    }

    @Test("requestHealthPermission keeps access unconfirmed when no readable samples exist")
    func requestHealthPermissionKeepsAccessUnconfirmed() async {
        let originalHealth = SharedStorage.healthPermissionGranted
        let originalHealthPromptShown = SharedStorage.healthAuthorizationPromptShown
        defer {
            SharedStorage.healthPermissionGranted = originalHealth
            SharedStorage.healthAuthorizationPromptShown = originalHealthPromptShown
        }

        // Simulate: the sheet was shown, but HealthKit still cannot prove readable data.
        let healthService = MockHealthService()
        await healthService.setMockAuthorizationStatus(.notDetermined)
        await healthService.setMockAuthorizationPromptShown(true)

        let sut = OnboardingViewModel(
            healthService: healthService,
            blockerService: MockBlockerService()
        )

        await sut.requestHealthPermission()

        #expect(sut.healthPermissionGranted == false)
        #expect(sut.healthAuthorizationStatus == .unconfirmed)
        #expect(sut.healthAuthorizationPromptShown == true)
        #expect(sut.errorMessage == nil)
        #expect(SharedStorage.healthPermissionGranted == false)
        #expect(SharedStorage.healthAuthorizationPromptShown == true)
    }

    @Test("requestScreenTimePermission marks Screen Time as granted on success")
    func requestScreenTimePermissionMarksGrantedOnSuccess() async {
        let originalScreenTime = SharedStorage.screenTimePermissionGranted
        defer { SharedStorage.screenTimePermissionGranted = originalScreenTime }

        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )

        await sut.requestScreenTimePermission()

        #expect(sut.screenTimePermissionGranted == true)
        #expect(sut.errorMessage == nil)
        #expect(SharedStorage.screenTimePermissionGranted == true)
    }

    @Test("advanceToNextStep advances through the onboarding flow")
    func advanceToNextStepAdvancesThroughFlow() {
        let originalHealth = SharedStorage.healthPermissionGranted
        let originalScreenTime = SharedStorage.screenTimePermissionGranted
        defer {
            SharedStorage.healthPermissionGranted = originalHealth
            SharedStorage.screenTimePermissionGranted = originalScreenTime
        }
        SharedStorage.healthPermissionGranted = false
        SharedStorage.screenTimePermissionGranted = false

        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )

        #expect(sut.currentStep == .welcome)

        sut.advanceToNextStep()
        #expect(sut.currentStep == .setupGoal)

        sut.advanceToNextStep()
        #expect(sut.currentStep == .health)

        sut.advanceToNextStep()
        #expect(sut.currentStep == .screenTime)

        sut.advanceToNextStep()
        #expect(sut.currentStep == .chooseApps)

        sut.advanceToNextStep()
        #expect(sut.currentStep == .success)
    }

    @Test("advanceToNextStep skips screenTime when already granted")
    func advanceSkipsScreenTimeWhenGranted() {
        let originalScreenTime = SharedStorage.screenTimePermissionGranted
        defer { SharedStorage.screenTimePermissionGranted = originalScreenTime }
        SharedStorage.screenTimePermissionGranted = true

        let blockerService = MockBlockerService()

        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: blockerService
        )
        sut.currentStep = .health

        sut.advanceToNextStep()
        #expect(sut.currentStep == .chooseApps)
    }

    @Test("advanceToNextStep skips health when already granted")
    func advanceSkipsHealthWhenGranted() {
        let originalHealth = SharedStorage.healthPermissionGranted
        let originalScreenTime = SharedStorage.screenTimePermissionGranted
        defer {
            SharedStorage.healthPermissionGranted = originalHealth
            SharedStorage.screenTimePermissionGranted = originalScreenTime
        }
        SharedStorage.healthPermissionGranted = true
        SharedStorage.screenTimePermissionGranted = false

        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.currentStep = .setupGoal

        sut.advanceToNextStep()
        #expect(sut.currentStep == .screenTime)
    }

    @Test("advanceToNextStep shows health step for timeUnlock goal")
    func advanceShowsHealthForTimeUnlockGoal() {
        let originalHealth = SharedStorage.healthPermissionGranted
        defer { SharedStorage.healthPermissionGranted = originalHealth }
        SharedStorage.healthPermissionGranted = false

        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .timeUnlock)
        sut.currentStep = .setupGoal

        sut.advanceToNextStep()
        #expect(sut.currentStep == .health)
    }
    
    // MARK: - Goal Configuration (Story 2)
    
    @Test("configureGoal sets correct defaults for steps")
    func configureGoalSetsStepsDefaults() {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        
        sut.configureGoal(type: .steps)
        
        #expect(sut.selectedGoalType == .steps)
        #expect(sut.goalTarget == 8_000)
        #expect(sut.selectedDays == Set(Weekday.allCases))
    }
    
    @Test("configureGoal sets correct defaults for activeEnergy")
    func configureGoalSetsActiveEnergyDefaults() {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        
        sut.configureGoal(type: .activeEnergy)
        
        #expect(sut.selectedGoalType == .activeEnergy)
        #expect(sut.goalTarget == 500)
    }
    
    @Test("configureGoal sets correct defaults for exercise")
    func configureGoalSetsExerciseDefaults() {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        
        sut.configureGoal(type: .exercise)
        
        #expect(sut.selectedGoalType == .exercise)
        #expect(sut.goalTarget == 30)
        #expect(sut.selectedExerciseType == .any)
    }
    
    @Test("configureGoal sets correct defaults for timeUnlock")
    func configureGoalSetsTimeUnlockDefaults() {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        
        sut.configureGoal(type: .timeUnlock)
        
        #expect(sut.selectedGoalType == .timeUnlock)
        #expect(sut.goalTarget == Double(19 * 60))
    }
    
    @Test("resetGoalSelection clears selected type")
    func resetGoalSelectionClearsType() {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .steps)
        #expect(sut.selectedGoalType == .steps)
        
        sut.resetGoalSelection()
        #expect(sut.selectedGoalType == nil)
    }
    
    @Test("isGoalConfigured returns false before configuration")
    func isGoalConfiguredFalseBeforeConfig() {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        
        #expect(sut.isGoalConfigured == false)
    }
    
    @Test("isGoalConfigured returns true after valid configuration")
    func isGoalConfiguredTrueAfterConfig() {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .steps)
        
        #expect(sut.isGoalConfigured == true)
    }
    
    @Test("selectedGoalRequiresHealth returns false for timeUnlock")
    func selectedGoalRequiresHealthFalseForTimeUnlock() {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .timeUnlock)
        
        #expect(sut.selectedGoalRequiresHealth == false)
    }
    
    @Test("selectedGoalRequiresHealth returns true for health-based goals",
          arguments: [GoalType.steps, GoalType.activeEnergy, GoalType.exercise])
    func selectedGoalRequiresHealthTrueForHealthGoals(goalType: GoalType) {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: goalType)
        
        #expect(sut.selectedGoalRequiresHealth == true)
    }
    
    @Test("saveOnboardingGoal persists steps goal to storage")
    func saveOnboardingGoalPersistsSteps() {
        let originalGoal = HealthGoal.load()
        defer { HealthGoal.save(originalGoal) }
        
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .steps)
        sut.goalTarget = 10_000
        
        sut.saveOnboardingGoal()
        
        let saved = HealthGoal.load()
        #expect(saved.stepGoal.isEnabled == true)
        #expect(saved.stepGoal.target == 10_000)
        #expect(saved.stepGoal.schedule == .everyDay)
        #expect(saved.activeEnergyGoal.isEnabled == false)
        #expect(saved.exerciseGoals.isEmpty)
        #expect(saved.timeBlockGoal.isEnabled == false)
    }
    
    @Test("saveOnboardingGoal persists exercise goal with type")
    func saveOnboardingGoalPersistsExercise() {
        let originalGoal = HealthGoal.load()
        defer { HealthGoal.save(originalGoal) }
        
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .exercise)
        sut.goalTarget = 45
        sut.selectedExerciseType = .running
        
        sut.saveOnboardingGoal()
        
        let saved = HealthGoal.load()
        #expect(saved.stepGoal.isEnabled == false)
        #expect(saved.exerciseGoals.count == 1)
        #expect(saved.exerciseGoals.first?.isEnabled == true)
        #expect(saved.exerciseGoals.first?.targetMinutes == 45)
        #expect(saved.exerciseGoals.first?.exerciseType == .running)
        #expect(saved.activeEnergyGoal.isEnabled == false)
        #expect(saved.timeBlockGoal.isEnabled == false)
    }
    
    @Test("saveOnboardingGoal persists timeUnlock goal")
    func saveOnboardingGoalPersistsTimeUnlock() {
        let originalGoal = HealthGoal.load()
        defer { HealthGoal.save(originalGoal) }
        
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .timeUnlock)
        sut.goalTarget = Double(20 * 60) // 8 PM
        
        sut.saveOnboardingGoal()
        
        let saved = HealthGoal.load()
        #expect(saved.stepGoal.isEnabled == false)
        #expect(saved.activeEnergyGoal.isEnabled == false)
        #expect(saved.exerciseGoals.isEmpty)
        #expect(saved.timeBlockGoal.isEnabled == true)
        #expect(saved.timeBlockGoal.unlockTimeMinutes == 20 * 60)
    }
    
    @Test("saveOnboardingGoal respects custom repeat schedule")
    func saveOnboardingGoalRespectsSchedule() {
        let originalGoal = HealthGoal.load()
        defer { HealthGoal.save(originalGoal) }
        
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .steps)
        sut.selectedDays = [.monday, .wednesday, .friday]
        
        sut.saveOnboardingGoal()
        
        let saved = HealthGoal.load()
        #expect(saved.stepGoal.schedule == .recurring([.monday, .wednesday, .friday]))
    }
    
    @Test("goalSummaryText formats steps correctly")
    func goalSummaryTextSteps() {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .steps)
        sut.goalTarget = 10_000
        
        #expect(sut.goalSummaryText.contains("10,000"))
        #expect(sut.goalSummaryText.contains("steps"))
    }
    
    @Test("goalSummaryText formats timeUnlock correctly")
    func goalSummaryTextTimeUnlock() {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .timeUnlock)
        
        #expect(sut.goalSummaryText.lowercased().contains("unlock"))
    }
    
    // MARK: - Permission Skip Logic
    
    @Test("advanceToNextStep skips health and screenTime when all permissions pre-granted")
    func advanceSkipsPermissionsWhenAllGranted() {
        let originalHealth = SharedStorage.healthPermissionGranted
        let originalScreenTime = SharedStorage.screenTimePermissionGranted
        defer {
            SharedStorage.healthPermissionGranted = originalHealth
            SharedStorage.screenTimePermissionGranted = originalScreenTime
        }
        SharedStorage.healthPermissionGranted = true
        SharedStorage.screenTimePermissionGranted = true
        
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .steps)
        sut.currentStep = .setupGoal
        
        sut.advanceToNextStep()
        // Should skip health and screenTime — land on chooseApps
        #expect(sut.currentStep == .chooseApps)
    }
    
    @Test("advanceToNextStep skips health and screenTime for timeUnlock when all pre-granted")
    func advanceSkipsPermissionsForTimeUnlockWhenAllGranted() {
        let originalHealth = SharedStorage.healthPermissionGranted
        let originalScreenTime = SharedStorage.screenTimePermissionGranted
        defer {
            SharedStorage.healthPermissionGranted = originalHealth
            SharedStorage.screenTimePermissionGranted = originalScreenTime
        }
        SharedStorage.healthPermissionGranted = true
        SharedStorage.screenTimePermissionGranted = true
        
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )
        sut.configureGoal(type: .timeUnlock)
        sut.currentStep = .setupGoal
        
        sut.advanceToNextStep()
        #expect(sut.currentStep == .chooseApps)
    }
}