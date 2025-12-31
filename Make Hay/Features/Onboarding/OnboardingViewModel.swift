//
//  OnboardingViewModel.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import Foundation
import Combine

/// Represents the steps in the onboarding flow.
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case health = 1
    case screenTime = 2
    case done = 3
}

/// ViewModel managing the onboarding flow state and permission requests.
/// Uses @MainActor isolation to ensure all UI state updates happen on the main thread.
@MainActor
final class OnboardingViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// The current step in the onboarding flow.
    @Published var currentStep: OnboardingStep = .welcome
    
    /// Whether HealthKit permission has been granted.
    @Published var healthPermissionGranted: Bool = false
    
    /// Whether Screen Time permission has been granted.
    @Published var screenTimePermissionGranted: Bool = false
    
    /// Whether a permission request is currently in progress.
    @Published var isRequestingPermission: Bool = false
    
    /// Error message to display if a permission request fails.
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    
    /// The health service for HealthKit operations.
    private let healthService: any HealthServiceProtocol
    
    /// The blocker service for Screen Time/FamilyControls operations.
    private let blockerService: any BlockerServiceProtocol
    
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
    }
    
    // MARK: - Navigation
    
    /// Advances to the next onboarding step.
    func goToNextStep() {
        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = nextStep
    }
    
    /// Returns to the previous onboarding step.
    func goToPreviousStep() {
        guard let previousStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previousStep
    }
    
    /// Whether the user can proceed to the next step from the current position.
    var canProceed: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .health:
            return healthPermissionGranted
        case .screenTime:
            return screenTimePermissionGranted
        case .done:
            return true
        }
    }
    
    // MARK: - Permission Requests
    
    /// Requests HealthKit authorization.
    /// Updates `healthPermissionGranted` on success or `errorMessage` on failure.
    func requestHealthPermission() async {
        errorMessage = nil
        isRequestingPermission = true
        
        do {
            try await healthService.requestAuthorization()
            healthPermissionGranted = true
        } catch let error as HealthServiceError {
            errorMessage = error.errorDescription
            healthPermissionGranted = false
        } catch {
            errorMessage = error.localizedDescription
            healthPermissionGranted = false
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
        } catch let error as BlockerServiceError {
            errorMessage = error.errorDescription
            screenTimePermissionGranted = false
        } catch {
            errorMessage = error.localizedDescription
            screenTimePermissionGranted = false
        }
        
        isRequestingPermission = false
    }
    
    /// Clears any displayed error message.
    func dismissError() {
        errorMessage = nil
    }
}

