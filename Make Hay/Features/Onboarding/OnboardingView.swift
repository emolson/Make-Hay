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
    
    /// Services read from the environment — no init params needed.
    /// **Why `@Environment`?** Removes service-threading from `Make_HayApp` and makes
    /// previews zero-config via mock defaults in `EnvironmentKeys.swift`.
    @Environment(\.healthService) private var healthService
    @Environment(\.blockerService) private var blockerService
    @Environment(\.openURL) private var openURL
    
    /// ViewModel managing onboarding state and permission requests.
    /// **Why optional?** Services from `@Environment` aren't available in `init`,
    /// so the VM is created lazily in `.task`. The one-frame `nil` state is imperceptible.
    @State private var viewModel: OnboardingViewModel?
    
    var body: some View {
        Group {
            if let viewModel {
                onboardingContent(viewModel: viewModel)
            } else {
                Color.clear
            }
        }
        .task {
            if viewModel == nil {
                let onboardingViewModel = OnboardingViewModel(
                    healthService: healthService,
                    blockerService: blockerService
                )
                viewModel = onboardingViewModel
                await onboardingViewModel.refreshPermissionState()
            }
        }
    }
    
    @ViewBuilder
    private func onboardingContent(viewModel: OnboardingViewModel) -> some View {
        TabView(selection: Binding(
            get: { viewModel.currentStep },
            set: { viewModel.currentStep = $0 }
        )) {
            WelcomeStepView(onContinue: viewModel.goToNextStep)
                .tag(OnboardingStep.welcome)
            
            HealthPermissionStepView(
                isPermissionGranted: viewModel.healthPermissionGranted,
                isLoading: viewModel.isRequestingPermission,
                errorMessage: viewModel.errorMessage,
                onRequestPermission: {
                    Task { await viewModel.requestHealthPermission() }
                },
                onSkip: viewModel.goToNextStep,
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
                onOpenSettings: openAppSettings,
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
        // **Why disable scrolling?** The paged TabView allows free swiping between
        // steps, which lets users skip the Health and Screen Time permission gates.
        // Disabling scroll forces navigation through the gated "Continue" buttons.
        .scrollDisabled(true)
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
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
                .foregroundStyle(Color.onboardingWelcome)
                .accessibilityIdentifier("welcomeIcon")
            
            Text(String(localized: "Welcome to Make Hay"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "Two quick permissions to get started."))
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
    let onSkip: () -> Void
    let onContinue: () -> Void
    let onDismissError: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: isPermissionGranted ? "heart.fill" : "heart")
                .font(.system(size: 80))
                .foregroundStyle(isPermissionGranted ? Color.statusSuccess : Color.statusError)
                .accessibilityIdentifier("healthIcon")
            
            Text(String(localized: "Allow Apple Health"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "Used to read your health goal progress."))
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
                VStack(spacing: 12) {
                    OnboardingButton(
                        title: String(localized: "Allow Health"),
                        isLoading: isLoading,
                        action: onRequestPermission
                    )
                    .accessibilityIdentifier("connectHealthButton")

                    SecondaryOnboardingButton(
                        title: String(localized: "Skip for Now"),
                        action: onSkip
                    )
                    .accessibilityIdentifier("skipHealthButton")
                }
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
    let onOpenSettings: () -> Void
    let onDismissError: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: isPermissionGranted ? "hourglass.badge.plus" : "hourglass")
                .font(.system(size: 80))
                .foregroundStyle(isPermissionGranted ? Color.statusSuccess : Color.statusPermissionPending)
                .accessibilityIdentifier("screenTimeIcon")
            
            Text(String(localized: "Allow Screen Time"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "Needed to block apps until you hit your goals."))
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
                VStack(spacing: 12) {
                    OnboardingButton(
                        title: String(localized: "Allow Screen Time"),
                        isLoading: isLoading,
                        action: onRequestPermission
                    )
                    .accessibilityIdentifier("enableScreenTimeButton")

                    if errorMessage != nil {
                        SecondaryOnboardingButton(
                            title: String(localized: "Open Settings"),
                            action: onOpenSettings
                        )
                        .accessibilityIdentifier("openScreenTimeSettingsButton")
                    }
                }
            }
            
            Spacer()
                .frame(height: 60)
        }
        .padding()
    }
}

/// Completion step confirming permission setup is done.
private struct CompletionStepView: View {
    let onGetStarted: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.statusSuccess)
                .accessibilityIdentifier("completionIcon")
            
            Text(String(localized: "Ready to Start"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "Next, add a goal and choose apps to block."))
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
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.onboardingButtonContent))
                } else {
                    Text(title)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(Color.onboardingButtonContent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isLoading)
        .padding(.horizontal, 24)
    }
}

/// A secondary styled button for onboarding actions (greyed out secondary action).
private struct SecondaryOnboardingButton: View {
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.onboardingSecondaryBackground)
                .foregroundStyle(Color.onboardingSecondaryContent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 24)
    }
}

/// Badge indicating permission has been granted.
private struct PermissionGrantedBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.statusSuccess)
            Text(String(localized: "Permission Granted"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.statusSuccess)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.statusSuccess.opacity(0.1))
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
                .foregroundStyle(Color.statusError)
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.statusError)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.statusError.opacity(0.7))
            }
            .accessibilityLabel(String(localized: "Dismiss error"))
        }
        .padding()
        .background(Color.statusError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }
}

// MARK: - Preview

#Preview("Onboarding Flow") {
    OnboardingView(
        hasCompletedOnboarding: .constant(false)
    )
}

#Preview("Health Step - Not Granted") {
    HealthPermissionStepView(
        isPermissionGranted: false,
        isLoading: false,
        errorMessage: nil,
        onRequestPermission: {},
        onSkip: {},
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
        onSkip: {},
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
        onSkip: {},
        onContinue: {},
        onDismissError: {}
    )
}

#Preview("Screen Time Step - Not Granted") {
    ScreenTimePermissionStepView(
        isPermissionGranted: false,
        isLoading: false,
        errorMessage: nil,
        onRequestPermission: {},
        onContinue: {},
        onOpenSettings: {},
        onDismissError: {}
    )
}

#Preview("Screen Time Step - Granted") {
    ScreenTimePermissionStepView(
        isPermissionGranted: true,
        isLoading: false,
        errorMessage: nil,
        onRequestPermission: {},
        onContinue: {},
        onOpenSettings: {},
        onDismissError: {}
    )
}

#Preview("Screen Time Step - Error") {
    ScreenTimePermissionStepView(
        isPermissionGranted: false,
        isLoading: false,
        errorMessage: "Screen Time access was denied.",
        onRequestPermission: {},
        onContinue: {},
        onOpenSettings: {},
        onDismissError: {}
    )
}
