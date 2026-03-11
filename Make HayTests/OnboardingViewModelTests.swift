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
        let originalScreenTime = SharedStorage.screenTimePermissionGranted
        defer {
            SharedStorage.healthPermissionGranted = originalHealth
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
        #expect(sut.screenTimePermissionGranted == false)
        #expect(SharedStorage.healthPermissionGranted == true)
        #expect(SharedStorage.screenTimePermissionGranted == false)
    }

    @Test("requestHealthPermission marks Health as granted on success")
    func requestHealthPermissionMarksGrantedOnSuccess() async {
        let originalHealth = SharedStorage.healthPermissionGranted
        defer { SharedStorage.healthPermissionGranted = originalHealth }

        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )

        await sut.requestHealthPermission()

        #expect(sut.healthPermissionGranted == true)
        #expect(sut.errorMessage == nil)
        #expect(SharedStorage.healthPermissionGranted == true)
    }

    @Test("requestHealthPermission shows an error on failure")
    func requestHealthPermissionShowsErrorOnFailure() async {
        let originalHealth = SharedStorage.healthPermissionGranted
        defer { SharedStorage.healthPermissionGranted = originalHealth }

        let healthService = MockHealthService()
        await healthService.setShouldThrowError(true)

        let sut = OnboardingViewModel(
            healthService: healthService,
            blockerService: MockBlockerService()
        )

        await sut.requestHealthPermission()

        #expect(sut.healthPermissionGranted == false)
        #expect(sut.errorMessage?.isEmpty == false)
        #expect(SharedStorage.healthPermissionGranted == false)
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

    @Test("goToNextStep advances through the onboarding flow")
    func goToNextStepAdvancesThroughFlow() {
        let sut = OnboardingViewModel(
            healthService: MockHealthService(),
            blockerService: MockBlockerService()
        )

        #expect(sut.currentStep == .welcome)

        sut.goToNextStep()
        #expect(sut.currentStep == .health)

        sut.goToNextStep()
        #expect(sut.currentStep == .screenTime)

        sut.goToNextStep()
        #expect(sut.currentStep == .done)
    }
}