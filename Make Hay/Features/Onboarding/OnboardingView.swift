//
//  OnboardingView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI

/// Multi-step onboarding view guiding users through Health and Screen Time permission setup.
struct OnboardingView: View {
    /// Binding to track whether onboarding has been completed.
    @Binding var hasCompletedOnboarding: Bool
    
    /// ViewModel managing onboarding state and permission requests.
    @State private var viewModel: OnboardingViewModel
    
    /// Creates a new OnboardingView with the specified services.
    /// - Parameters:
    ///   - hasCompletedOnboarding: Binding to the onboarding completion state.
    ///   - healthService: The health service for HealthKit operations.
    ///   - blockerService: The blocker service for Screen Time operations.
    init(
        hasCompletedOnboarding: Binding<Bool>,
        healthService: any HealthServiceProtocol,
        blockerService: any BlockerServiceProtocol
    ) {
        self._hasCompletedOnboarding = hasCompletedOnboarding
        self._viewModel = State(initialValue: OnboardingViewModel(
            healthService: healthService,
            blockerService: blockerService
        ))
    }
    
    var body: some View {
        TabView(selection: $viewModel.currentStep) {
            WelcomeStepView(onContinue: viewModel.goToNextStep)
                .tag(OnboardingStep.welcome)
            
            HealthPermissionStepView(
                isPermissionGranted: viewModel.healthPermissionGranted,
                isLoading: viewModel.isRequestingPermission,
                errorMessage: viewModel.errorMessage,
                onRequestPermission: {
                    Task { await viewModel.requestHealthPermission() }
                },
                onContinue: viewModel.goToNextStep,
                onDismissError: viewModel.dismissError
            )
            .tag(OnboardingStep.health)
            
            ScreenTimePermissionStepView(
                isPermissionGranted: viewModel.screenTimePermissionGranted,
                isLoading: viewModel.isRequestingPermission,
                errorMessage: viewModel.errorMessage,
                onRequestPermission: {
                    Task { await viewModel.requestScreenTimePermission() }
                },
                onContinue: viewModel.goToNextStep,
                onDismissError: viewModel.dismissError
            )
            .tag(OnboardingStep.screenTime)
            
            CompletionStepView(onGetStarted: {
                hasCompletedOnboarding = true
            })
            .tag(OnboardingStep.done)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .animation(.easeInOut, value: viewModel.currentStep)
    }
}

// MARK: - Step Views

/// Welcome step explaining the app concept.
private struct WelcomeStepView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "sun.max.fill")
                .font(.system(size: 80))
                .foregroundStyle(.yellow)
                .accessibilityIdentifier("welcomeIcon")
            
            Text(String(localized: "Welcome to Make Hay"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "Earn your screen time by hitting your health goals."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            OnboardingButton(
                title: String(localized: "Continue"),
                action: onContinue
            )
            .accessibilityIdentifier("welcomeContinueButton")
            
            Spacer()
                .frame(height: 60)
        }
        .padding()
    }
}

/// Health permission step for requesting HealthKit authorization.
private struct HealthPermissionStepView: View {
    let isPermissionGranted: Bool
    let isLoading: Bool
    let errorMessage: String?
    let onRequestPermission: () -> Void
    let onContinue: () -> Void
    let onDismissError: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: isPermissionGranted ? "heart.fill" : "heart")
                .font(.system(size: 80))
                .foregroundStyle(isPermissionGranted ? .green : .red)
                .accessibilityIdentifier("healthIcon")
            
            Text(String(localized: "Connect Apple Health"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "We need access to your step count to track your daily progress and unlock your apps."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            if isPermissionGranted {
                PermissionGrantedBadge()
                    .accessibilityIdentifier("healthPermissionGrantedBadge")
            }
            
            if let errorMessage {
                ErrorMessageView(message: errorMessage, onDismiss: onDismissError)
                    .accessibilityIdentifier("healthErrorMessage")
            }
            
            Spacer()
            
            if isPermissionGranted {
                OnboardingButton(
                    title: String(localized: "Continue"),
                    action: onContinue
                )
                .accessibilityIdentifier("healthContinueButton")
            } else {
                OnboardingButton(
                    title: String(localized: "Connect Apple Health"),
                    isLoading: isLoading,
                    action: onRequestPermission
                )
                .accessibilityIdentifier("connectHealthButton")
            }
            
            Spacer()
                .frame(height: 60)
        }
        .padding()
    }
}

/// Screen Time permission step for requesting FamilyControls authorization.
private struct ScreenTimePermissionStepView: View {
    let isPermissionGranted: Bool
    let isLoading: Bool
    let errorMessage: String?
    let onRequestPermission: () -> Void
    let onContinue: () -> Void
    let onDismissError: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: isPermissionGranted ? "hourglass.badge.plus" : "hourglass")
                .font(.system(size: 80))
                .foregroundStyle(isPermissionGranted ? .green : .purple)
                .accessibilityIdentifier("screenTimeIcon")
            
            Text(String(localized: "Enable Screen Time"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "Allow Screen Time access to block distracting apps until you reach your daily step goal."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            if isPermissionGranted {
                PermissionGrantedBadge()
                    .accessibilityIdentifier("screenTimePermissionGrantedBadge")
            }
            
            if let errorMessage {
                ErrorMessageView(message: errorMessage, onDismiss: onDismissError)
                    .accessibilityIdentifier("screenTimeErrorMessage")
            }
            
            Spacer()
            
            if isPermissionGranted {
                OnboardingButton(
                    title: String(localized: "Continue"),
                    action: onContinue
                )
                .accessibilityIdentifier("screenTimeContinueButton")
            } else {
                OnboardingButton(
                    title: String(localized: "Enable Screen Time"),
                    isLoading: isLoading,
                    action: onRequestPermission
                )
                .accessibilityIdentifier("enableScreenTimeButton")
            }
            
            Spacer()
                .frame(height: 60)
        }
        .padding()
    }
}

/// Completion step confirming setup is done.
private struct CompletionStepView: View {
    let onGetStarted: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
                .accessibilityIdentifier("completionIcon")
            
            Text(String(localized: "You're All Set!"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "Start walking to earn your screen time. The more you move, the more you can use your favorite apps!"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
            
            OnboardingButton(
                title: String(localized: "Get Started"),
                action: onGetStarted
            )
            .accessibilityIdentifier("getStartedButton")
            
            Spacer()
                .frame(height: 60)
        }
        .padding()
    }
}

// MARK: - Reusable Components

/// A styled button for onboarding actions.
private struct OnboardingButton: View {
    let title: String
    var isLoading: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(title)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isLoading)
        .padding(.horizontal, 24)
    }
}

/// Badge indicating permission has been granted.
private struct PermissionGrantedBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(String(localized: "Permission Granted"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.1))
        .clipShape(Capsule())
    }
}

/// View displaying an error message with a dismiss button.
private struct ErrorMessageView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .accessibilityLabel(String(localized: "Dismiss error"))
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }
}

// MARK: - Preview

#Preview("Onboarding Flow") {
    OnboardingView(
        hasCompletedOnboarding: .constant(false),
        healthService: MockHealthService(),
        blockerService: MockBlockerService()
    )
}

#Preview("Health Step - Not Granted") {
    HealthPermissionStepView(
        isPermissionGranted: false,
        isLoading: false,
        errorMessage: nil,
        onRequestPermission: {},
        onContinue: {},
        onDismissError: {}
    )
}

#Preview("Health Step - Granted") {
    HealthPermissionStepView(
        isPermissionGranted: true,
        isLoading: false,
        errorMessage: nil,
        onRequestPermission: {},
        onContinue: {},
        onDismissError: {}
    )
}

#Preview("Health Step - Error") {
    HealthPermissionStepView(
        isPermissionGranted: false,
        isLoading: false,
        errorMessage: "Permission to access health data was denied.",
        onRequestPermission: {},
        onContinue: {},
        onDismissError: {}
    )
}
