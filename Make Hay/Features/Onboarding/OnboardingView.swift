//
//  OnboardingView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import FamilyControls
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
        @Bindable var vm = viewModel
        VStack(spacing: 0) {
            OnboardingProgressBar(progress: vm.stepProgress)
                .padding(.vertical, 12)

            TabView(selection: $vm.currentStep) {
                WelcomeStepView(onContinue: vm.advanceToNextStep)
                    .tag(OnboardingStep.welcome)

                SetupGoalStepView(viewModel: vm)
                    .tag(OnboardingStep.setupGoal)

                HealthPermissionStepView(
                    healthStatus: vm.healthAuthorizationStatus,
                    isPermissionGranted: vm.healthPermissionGranted,
                    isLoading: vm.isRequestingPermission,
                    errorMessage: vm.errorMessage,
                    selectedGoalRequiresHealth: vm.selectedGoalRequiresHealth,
                    onRequestPermission: {
                        Task { await vm.requestHealthPermission() }
                    },
                    onOpenHealthApp: openHealthApp,
                    onSkip: vm.advanceToNextStep,
                    onContinue: vm.advanceToNextStep,
                    onDismissError: vm.dismissError
                )
                .tag(OnboardingStep.health)

                ScreenTimePermissionStepView(
                    isPermissionGranted: vm.screenTimePermissionGranted,
                    isLoading: vm.isRequestingPermission,
                    isDenied: vm.screenTimeDenied,
                    errorMessage: vm.errorMessage,
                    goalSummaryText: vm.goalSummaryText,
                    onRequestPermission: {
                        Task { await vm.requestScreenTimePermission() }
                    },
                    onContinue: vm.advanceToNextStep,
                    onOpenSettings: openAppSettings,
                    onDismissError: vm.dismissError
                )
                .tag(OnboardingStep.screenTime)

                ChooseAppsStepView(viewModel: vm)
                    .tag(OnboardingStep.chooseApps)

                SuccessStepView(viewModel: vm, onGoToDashboard: {
                    hasCompletedOnboarding = true
                })
                .tag(OnboardingStep.success)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .scrollDisabled(true)
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(settingsURL)
    }

    private func openHealthApp() {
        openAppSettings()
    }
}

// MARK: - Step Views

/// Welcome step explaining the app concept.
private struct WelcomeStepView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Hero Graphic with Depth and Motion
            ZStack {
                Circle()
                    .fill(Color.onboardingWelcome.opacity(0.15))
                    .frame(width: 160, height: 160)
                
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 80))
                    .symbolRenderingMode(.multicolor)
                    .foregroundStyle(Color.onboardingWelcome)
                    .symbolEffect(.breathe, options: .repeating)
                    .shadow(color: Color.onboardingWelcome.opacity(0.3), radius: 10, y: 5)
                    .accessibilityIdentifier("welcomeIcon")
            }
            .padding(.bottom, 48)
            
            // Stacked Typography Hierarchy
            VStack(spacing: 12) {
                Text(String(localized: "Move More.\nScroll Less."))
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                
                Text(String(localized: "Make every day count. Make Hay blocks your apps until your fitness goals are met."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
            
            OnboardingButton(
                title: String(localized: "Continue"),
                action: onContinue
            )
            .accessibilityIdentifier("welcomeContinueButton")
            
            Spacer()
                .frame(height: 40)
        }
        .padding()
    }
}

/// Health permission step for requesting HealthKit authorization.
private struct HealthPermissionStepView: View {
    let healthStatus: HealthAuthorizationStatus
    let isPermissionGranted: Bool
    let isLoading: Bool
    let errorMessage: String?
    let selectedGoalRequiresHealth: Bool
    let onRequestPermission: () -> Void
    let onOpenHealthApp: () -> Void
    let onSkip: () -> Void
    let onContinue: () -> Void
    let onDismissError: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: healthIconName)
                .font(.system(size: 80))
                .foregroundStyle(healthIconColor)
                .accessibilityIdentifier("healthIcon")
            
            Text(String(localized: "Connect Apple Health"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            if selectedGoalRequiresHealth {
                Text(String(localized: "We'll automatically track your progress and unlock your apps the moment you hit your goal. Your health data never leaves your device."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Text(String(localized: "Connect Apple Health to track your activity even when using a time-based goal. Your health data never leaves your device."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            if isPermissionGranted {
                PermissionGrantedBadge()
                    .accessibilityIdentifier("healthPermissionGrantedBadge")
            } else if healthStatus == .unconfirmed {
                Text(String(localized: "Apple Health access was requested. If tracking has not started yet, open the Health app and make sure all categories are enabled."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .accessibilityIdentifier("healthPermissionUnconfirmedMessage")
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
                        title: primaryButtonTitle,
                        isLoading: isLoading,
                        action: primaryButtonAction
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

    private var healthIconName: String {
        switch healthStatus {
        case .authorized:
            return "heart.fill"
        case .unconfirmed:
            return "heart.text.square"
        case .denied:
            return "heart.slash"
        case .notDetermined:
            return "heart"
        }
    }

    private var healthIconColor: Color {
        switch healthStatus {
        case .authorized:
            return Color.statusSuccess
        case .unconfirmed:
            return Color.statusWarning
        case .denied:
            return Color.statusError
        case .notDetermined:
            return Color.statusPermissionPending
        }
    }

    private var primaryButtonTitle: String {
        switch healthStatus {
        case .authorized:
            return String(localized: "Continue")
        case .unconfirmed, .denied:
            return String(localized: "Open Settings")
        case .notDetermined:
            return String(localized: "Connect Apple Health")
        }
    }

    private var primaryButtonAction: () -> Void {
        switch healthStatus {
        case .unconfirmed, .denied:
            return onOpenHealthApp
        case .authorized, .notDetermined:
            return onRequestPermission
        }
    }
}

/// Screen Time permission step for requesting FamilyControls authorization.
///
/// **Story 4:** Benefit-oriented copy referencing the user's configured goal.
/// Shows a persistent "Open Settings" recovery path when the user denies the prompt.
private struct ScreenTimePermissionStepView: View {
    let isPermissionGranted: Bool
    let isLoading: Bool
    let isDenied: Bool
    let errorMessage: String?
    let goalSummaryText: String
    let onRequestPermission: () -> Void
    let onContinue: () -> Void
    let onOpenSettings: () -> Void
    let onDismissError: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: isPermissionGranted ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 80))
                .foregroundStyle(isPermissionGranted ? Color.statusSuccess : Color.statusPermissionPending)
                .accessibilityIdentifier("screenTimeIcon")
            
            Text(String(localized: "Let's Lock In Your Commitment"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "Make Hay uses Screen Time to temporarily limit access to apps you choose until you reach your daily fitness goal. You stay in control and can revoke this permission at any time in Settings."))
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
            
            if isDenied && errorMessage == nil {
                denialRecoveryMessage
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

                    if isDenied {
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
    
    /// Persistent recovery message shown after the user denies Screen Time
    /// and then dismisses the error banner.
    private var denialRecoveryMessage: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.statusWarning)
            
            Text(String(localized: "Screen Time was denied. You can enable it in Settings to continue."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.statusWarning.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
        .accessibilityIdentifier("screenTimeDenialRecovery")
    }
}

/// Goal setup step where the user selects a goal type and configures its target.
///
/// **Two-phase UI:** Phase A shows a card grid of goal types. Phase B shows
/// configuration controls (stepper/DatePicker + repeat day picker) for the
/// selected type. No NavigationStack — conditional rendering keeps it flat
/// within the paged TabView.
private struct SetupGoalStepView: View {
    @Bindable var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            if viewModel.selectedGoalType == nil {
                goalTypeSelectionPhase
            } else {
                goalConfigurationPhase
            }
        }
        .padding()
    }
    
    // MARK: - Phase A: Goal Type Selection
    
    private var goalTypeSelectionPhase: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "target")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("setupGoalIcon")
            
            Text(String(localized: "Set Your First Goal"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(GoalType.allCases) { goalType in
                    OnboardingGoalTypeCard(goalType: goalType) {
                        viewModel.configureGoal(type: goalType)
                    }
                }
            }
            .padding(.horizontal, 8)
            
            Spacer()
            Spacer()
                .frame(height: 60)
        }
    }
    
    // MARK: - Phase B: Goal Configuration
    
    @ViewBuilder
    private var goalConfigurationPhase: some View {
        if let goalType = viewModel.selectedGoalType {
            VStack(spacing: 20) {
                Spacer()
                
                goalHeader(for: goalType)
                
                configurationControls(for: goalType)
                    .padding(.horizontal, 8)
                
                repeatDaySection
                    .padding(.horizontal, 8)
                
                Spacer()
                
                VStack(spacing: 12) {
                    OnboardingButton(
                        title: String(localized: "Continue"),
                        action: {
                            viewModel.saveOnboardingGoal()
                            viewModel.advanceToNextStep()
                        }
                    )
                    .disabled(!viewModel.isGoalConfigured)
                    .accessibilityIdentifier("setupGoalContinueButton")
                    
                    SecondaryOnboardingButton(
                        title: String(localized: "Choose Different Goal"),
                        action: viewModel.resetGoalSelection
                    )
                    .accessibilityIdentifier("chooseAnotherGoalButton")
                }
                
                Spacer()
                    .frame(height: 60)
            }
        }
    }
    
    private func goalHeader(for goalType: GoalType) -> some View {
        HStack(spacing: 16) {
            Image(systemName: goalType.iconName)
                .font(.system(size: 40))
                .foregroundStyle(goalType.color)
                .frame(width: 60, height: 60)
                .background(goalType.color.opacity(0.1), in: Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(goalType.displayName)
                    .font(.headline)
                
                Text(goalType.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("goalHeader.\(goalType.rawValue)")
    }
    
    @ViewBuilder
    private func configurationControls(for goalType: GoalType) -> some View {
        VStack(spacing: 12) {
            switch goalType {
            case .steps:
                onboardingStepper(
                    value: $viewModel.goalTarget,
                    range: 1_000...50_000,
                    step: 500,
                    unit: String(localized: "steps"),
                    color: goalType.color
                )
                
            case .activeEnergy:
                onboardingStepper(
                    value: $viewModel.goalTarget,
                    range: 50...2_000,
                    step: 50,
                    unit: String(localized: "kcal"),
                    color: goalType.color
                )
                
            case .exercise:
                onboardingStepper(
                    value: $viewModel.goalTarget,
                    range: 5...180,
                    step: 5,
                    unit: String(localized: "minutes"),
                    color: goalType.color
                )
                
                Picker(String(localized: "Exercise Type"), selection: $viewModel.selectedExerciseType) {
                    ForEach(ExerciseType.allCases) { type in
                        Label(type.displayName, systemImage: type.iconName)
                            .tag(type)
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("exerciseTypePicker")
                
            case .timeUnlock:
                DatePicker(
                    String(localized: "Unlock Time"),
                    selection: $viewModel.unlockTime,
                    displayedComponents: .hourAndMinute
                )
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("unlockTimePicker")
                .onChange(of: viewModel.unlockTime) {
                    viewModel.syncUnlockTimeToGoalTarget()
                }
            }
            
            Text(goalType.configurationHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }
    
    private func onboardingStepper(value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String, color: Color) -> some View {
        HStack {
            Text("\(Int(value.wrappedValue)) \(unit)")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.numericText())
                .animation(.snappy, value: value.wrappedValue)
            
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .accessibilityIdentifier("goalStepper")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var repeatDaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Repeat"))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 6) {
                ForEach(Weekday.orderedCases) { day in
                    Button {
                        if viewModel.selectedDays.contains(day) {
                            viewModel.selectedDays.remove(day)
                        } else {
                            viewModel.selectedDays.insert(day)
                        }
                    } label: {
                        Text(day.shortName.prefix(1))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 36, height: 36)
                            .foregroundStyle(viewModel.selectedDays.contains(day) ? Color.onboardingButtonContent : .primary)
                            .background(
                                viewModel.selectedDays.contains(day)
                                    ? Color.accentColor
                                    : Color(.systemGray5),
                                in: Circle()
                            )
                    }
                    .accessibilityIdentifier("dayToggle.\(day.shortName)")
                    .accessibilityLabel(day.fullName)
                    .accessibilityAddTraits(viewModel.selectedDays.contains(day) ? .isSelected : [])
                }
            }
            
            Text(GoalSchedule.from(weekdays: viewModel.selectedDays).displaySummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("repeatScheduleSection")
    }
}

/// Card representing a selectable goal type during onboarding.
private struct OnboardingGoalTypeCard: View {
    let goalType: GoalType
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: goalType.iconName)
                    .font(.system(size: 40))
                    .foregroundStyle(goalType.color)
                
                Text(goalType.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(goalType.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("goalTypeCard.\(goalType.rawValue)")
    }
}

/// Blocked-app selection step using the system `FamilyActivityPicker`.
///
/// **Story 5:** Presents the picker inline during onboarding so the user
/// selects blocked apps before reaching the Dashboard. Persists to the same
/// `FamilyActivitySelection` storage used by `AppPickerView` in Settings.
private struct ChooseAppsStepView: View {
    @Bindable var viewModel: OnboardingViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)
                .accessibilityIdentifier("chooseAppsIcon")
            
            Text(String(localized: "Choose Apps to Block"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "Pick the 2 or 3 apps that distract you the most — like social media or games. You can always change this later."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            selectionSummary
            
            Spacer()
            
            VStack(spacing: 12) {
                OnboardingButton(
                    title: viewModel.hasSelectedApps
                        ? String(localized: "Edit App Selection")
                        : String(localized: "Select Apps to Block"),
                    action: viewModel.presentAppPicker
                )
                .accessibilityIdentifier("selectAppsButton")
                
                SecondaryOnboardingButton(
                    title: String(localized: "Continue"),
                    action: viewModel.advanceToNextStep
                )
                .accessibilityIdentifier("chooseAppsContinueButton")
            }
            
            Text(String(localized: "You can change your blocked apps anytime in Settings."))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
                .frame(height: 60)
        }
        .padding()
        .familyActivityPicker(
            isPresented: $viewModel.isAppPickerPresented,
            selection: $viewModel.appDraftSelection
        )
        .onChange(of: viewModel.isAppPickerPresented) { _, isPresented in
            if !isPresented {
                viewModel.appPickerDismissed()
            }
        }
    }
    
    // MARK: - Selection Summary
    
    @ViewBuilder
    private var selectionSummary: some View {
        if viewModel.hasSelectedApps {
            VStack(spacing: 8) {
                if viewModel.selectedAppCount > 0 {
                    Label(
                        String(localized: "\(viewModel.selectedAppCount) app(s) selected"),
                        systemImage: "app.fill"
                    )
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
                
                if viewModel.selectedCategoryCount > 0 {
                    Label(
                        String(localized: "\(viewModel.selectedCategoryCount) category(ies) selected"),
                        systemImage: "folder.fill"
                    )
                    .font(.subheadline)
                    .fontWeight(.medium)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.statusSuccess.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
            .accessibilityIdentifier("appSelectionSummary")
        } else if viewModel.hasOpenedAppPicker {
            Text(String(localized: "No apps selected yet — you can always add them in Settings."))
                .font(.subheadline)
                .foregroundStyle(Color.statusWarning)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityIdentifier("noAppsNudge")
        }
    }
}

/// Outcome-focused final step confirming the user's live setup.
///
/// Displays the configured goal, blocked-app count, and context-sensitive copy
/// so the user leaves onboarding with zero ambiguity about what happens next.
/// Triggers a success haptic and a confetti burst on appear.
private struct SuccessStepView: View {
    let viewModel: OnboardingViewModel
    let onGoToDashboard: () -> Void

    @State private var hasAppeared = false

    private var totalSelectedCount: Int {
        viewModel.selectedAppCount + viewModel.selectedCategoryCount
    }

    /// True when all success conditions are met: permissions granted, goal configured, apps chosen.
    private var allSetConfirmed: Bool {
        viewModel.screenTimePermissionGranted &&
        (!viewModel.selectedGoalRequiresHealth || viewModel.healthPermissionGranted) &&
        viewModel.isGoalConfigured &&
        viewModel.hasSelectedApps
    }

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.statusSuccess)
                    .accessibilityIdentifier("successIcon")

                Text(String(localized: "You're All Set!"))
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

                if allSetConfirmed {
                    Text(String(localized: "Your apps are blocked until you hit your goal."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Goal summary card
                if let goalType = viewModel.selectedGoalType {
                    HStack(spacing: 12) {
                        Image(systemName: goalType.iconName)
                            .font(.system(size: 28))
                            .foregroundStyle(goalType.color)
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(goalType.displayName)
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text(viewModel.goalSummaryText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("successGoalCard")
                }

                // Blocked-apps confirmation
                if totalSelectedCount > 0 {
                    Label(
                        totalSelectedCount == 1
                            ? String(localized: "1 app will be blocked")
                            : String(localized: "\(totalSelectedCount) apps will be blocked"),
                        systemImage: "lock.fill"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("successBlockedAppsLabel")
                }

                // Health-skipped recovery hint
                if viewModel.healthWasSkipped {
                    Text(String(localized: "Connect Apple Health anytime to start automatic tracking."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .accessibilityIdentifier("successHealthSkippedNote")
                }

                Spacer()

                OnboardingButton(
                    title: String(localized: "Go to Dashboard"),
                    action: onGoToDashboard
                )
                .accessibilityIdentifier("goToDashboardButton")

                Spacer()
                    .frame(height: 60)
            }
            .padding()

            // Confetti burst — rendered as a non-interactive overlay.
            ConfettiView()
                .allowsHitTesting(false)
        }
        .sensoryFeedback(.success, trigger: hasAppeared)
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
        }
    }
}

/// Short-lived confetti burst that fires once on appear to celebrate setup completion.
///
/// Each particle is a colored shape that travels outward from the center and fades out
/// over ~1.2 seconds. Driven by a single `phase` state variable animated from 0 → 1.
private struct ConfettiView: View {
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            ForEach(0..<30, id: \.self) { i in
                confettiParticle(index: i)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) {
                phase = 1
            }
        }
    }

    private func confettiParticle(index i: Int) -> some View {
        let angle = Double(i) * 12.0                      // 360° / 30 particles = 12° apart
        let rad = angle * .pi / 180
        let distance = 80.0 + Double(i % 5) * 20.0       // vary 80–160 pt
        let size = 6.0 + Double(i % 4) * 2.5             // vary 6–13.5 pt
        let isCircle = i.isMultiple(of: 3)
        let color = confettiColor(for: i)

        return Group {
            if isCircle {
                Circle()
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .frame(width: size * 1.5, height: size * 0.7)
                    .rotationEffect(.degrees(angle * 2))
            }
        }
        .foregroundStyle(color)
        .offset(
            x: cos(rad) * distance * phase,
            y: sin(rad) * distance * phase
        )
        .opacity(1.0 - phase * 0.95)
        .scaleEffect(0.3 + phase * 0.7)
    }

    private func confettiColor(for index: Int) -> Color {
        let colors: [Color] = [
            .statusSuccess, .accentColor, .goalSteps,
            .goalActiveEnergy, .goalExercise, .goalTimeUnlock
        ]
        return colors[index % colors.count]
    }
}

// MARK: - Reusable Components

/// Horizontal progress bar communicating the user's position through visible onboarding steps.
///
/// Uses a filled capsule (proportion-based, not segmented) so the indicator implies forward
/// momentum without revealing a fixed total step count. Auto-skipped steps are excluded from
/// both numerator and denominator so the bar never stalls or jumps unexpectedly.
private struct OnboardingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * max(0, min(1, progress)))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 24)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Onboarding progress"))
        .accessibilityValue(String(localized: "\(Int(progress * 100)) percent complete"))
    }
}

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
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.accentColor)
            .foregroundStyle(Color.onboardingButtonContent)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
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
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.onboardingSecondaryBackground)
                .foregroundStyle(Color.onboardingSecondaryContent)
                .clipShape(RoundedRectangle(cornerRadius: 16))
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
        healthStatus: .notDetermined,
        isPermissionGranted: false,
        isLoading: false,
        errorMessage: nil,
        selectedGoalRequiresHealth: true,
        onRequestPermission: {},
        onOpenHealthApp: {},
        onSkip: {},
        onContinue: {},
        onDismissError: {}
    )
}

#Preview("Health Step - Granted") {
    HealthPermissionStepView(
        healthStatus: .authorized,
        isPermissionGranted: true,
        isLoading: false,
        errorMessage: nil,
        selectedGoalRequiresHealth: true,
        onRequestPermission: {},
        onOpenHealthApp: {},
        onSkip: {},
        onContinue: {},
        onDismissError: {}
    )
}

#Preview("Health Step - Error") {
    HealthPermissionStepView(
        healthStatus: .notDetermined,
        isPermissionGranted: false,
        isLoading: false,
        errorMessage: "Permission to access health data was denied.",
        selectedGoalRequiresHealth: true,
        onRequestPermission: {},
        onOpenHealthApp: {},
        onSkip: {},
        onContinue: {},
        onDismissError: {}
    )
}

#Preview("Screen Time Step - Not Granted") {
    ScreenTimePermissionStepView(
        isPermissionGranted: false,
        isLoading: false,
        isDenied: false,
        errorMessage: nil,
        goalSummaryText: "Walk 10,000 steps every day",
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
        isDenied: false,
        errorMessage: nil,
        goalSummaryText: "Walk 10,000 steps every day",
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
        isDenied: true,
        errorMessage: "Screen Time access was denied.",
        goalSummaryText: "Walk 10,000 steps every day",
        onRequestPermission: {},
        onContinue: {},
        onOpenSettings: {},
        onDismissError: {}
    )
}

#Preview("Screen Time Step - Denied (error dismissed)") {
    ScreenTimePermissionStepView(
        isPermissionGranted: false,
        isLoading: false,
        isDenied: true,
        errorMessage: nil,
        goalSummaryText: "30 minutes of exercise every day",
        onRequestPermission: {},
        onContinue: {},
        onOpenSettings: {},
        onDismissError: {}
    )
}

#Preview("Success - All Set (Steps)") {
    let vm = OnboardingViewModel(
        healthService: MockHealthService(),
        blockerService: MockBlockerService()
    )
    vm.configureGoal(type: .steps)
    vm.healthAuthorizationStatus = .authorized
    vm.healthAuthorizationPromptShown = true
    vm.screenTimePermissionGranted = true
    return SuccessStepView(viewModel: vm, onGoToDashboard: {})
}

#Preview("Success - Health Skipped (Exercise)") {
    let vm = OnboardingViewModel(
        healthService: MockHealthService(),
        blockerService: MockBlockerService()
    )
    vm.configureGoal(type: .exercise)
    vm.goalTarget = 30
    vm.healthAuthorizationStatus = .unconfirmed
    vm.healthAuthorizationPromptShown = true
    vm.screenTimePermissionGranted = true
    return SuccessStepView(viewModel: vm, onGoToDashboard: {})
}

#Preview("Success - Time Unlock (No Health Step)") {
    let vm = OnboardingViewModel(
        healthService: MockHealthService(),
        blockerService: MockBlockerService()
    )
    vm.configureGoal(type: .timeUnlock)
    vm.screenTimePermissionGranted = true
    return SuccessStepView(viewModel: vm, onGoToDashboard: {})
}

#Preview("Progress Bar - Half") {
    OnboardingProgressBar(progress: 0.5)
        .padding(.vertical, 40)
}
