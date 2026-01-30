//
//  GoalConfigurationView.swift
//  Make Hay
//
//  Created by Ethan Olson on 1/30/26.
//

import SwiftUI

/// View for configuring a specific goal type's target value.
/// Provides appropriate input controls for each goal type.
///
/// **Why separate configuration view?** Each goal type has different units and constraints
/// (steps vs. calories vs. time). This view adapts its interface based on the goal type.
struct GoalConfigurationView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var viewModel: DashboardViewModel
    let goalType: GoalType
    
    @State private var targetValue: Double
    @State private var selectedExerciseType: ExerciseType = .any
    @State private var unlockTime: Date
    @State private var isSaving: Bool = false
    @State private var triggerSuccessHaptic: Bool = false
    
    // MARK: - Initialization
    
    /// Creates a GoalConfigurationView for the specified goal type.
    /// Pre-fills with existing values if the goal was previously configured.
    /// - Parameters:
    ///   - viewModel: The ViewModel managing dashboard state.
    ///   - goalType: The type of goal being configured.
    init(viewModel: DashboardViewModel, goalType: GoalType) {
        _viewModel = State(initialValue: viewModel)
        self.goalType = goalType
        
        // Initialize unlockTime with a default (only used for .timeUnlock goals)
        let defaultUnlockTime = viewModel.healthGoal.timeBlockGoal.unlockDate()
        _unlockTime = State(initialValue: defaultUnlockTime)
        
        // Pre-fill with existing values or smart defaults
        switch goalType {
        case .steps:
            _targetValue = State(initialValue: Double(viewModel.healthGoal.stepGoal.target))
        case .activeEnergy:
            _targetValue = State(initialValue: Double(viewModel.healthGoal.activeEnergyGoal.target))
        case .exercise:
            _targetValue = State(initialValue: Double(viewModel.healthGoal.exerciseGoal.targetMinutes))
            _selectedExerciseType = State(initialValue: viewModel.healthGoal.exerciseGoal.exerciseType)
        case .timeUnlock:
            _targetValue = State(initialValue: Double(viewModel.healthGoal.timeBlockGoal.unlockTimeMinutes))
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        Form {
            Section {
                headerSection
            }
            
            Section {
                configurationControls
            } header: {
                Text(String(localized: "Target"))
            } footer: {
                Text(goalType.configurationHint)
            }
            
            if goalType == .exercise {
                Section {
                    Picker(String(localized: "Exercise Type"), selection: $selectedExerciseType) {
                        ForEach(ExerciseType.allCases) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }
                } header: {
                    Text(String(localized: "Filter"))
                } footer: {
                    Text(String(localized: "Optionally filter to specific workout types"))
                }
            }
        }
        .navigationTitle(goalType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                        .accessibilityIdentifier("savingIndicator")
                } else {
                    Button(String(localized: "Add")) {
                        saveGoal()
                    }
                    .disabled(!isValidInput)
                    .accessibilityIdentifier("addGoalConfirmButton")
                }
            }
        }
        .disabled(isSaving)
        .sensoryFeedback(.success, trigger: triggerSuccessHaptic)
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
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
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var configurationControls: some View {
        switch goalType {
        case .steps:
            stepperControl(
                value: $targetValue,
                range: 1_000...50_000,
                step: 500,
                unit: String(localized: "steps")
            )
            
        case .activeEnergy:
            stepperControl(
                value: $targetValue,
                range: 50...2_000,
                step: 50,
                unit: String(localized: "kcal")
            )
            
        case .exercise:
            stepperControl(
                value: $targetValue,
                range: 5...180,
                step: 5,
                unit: String(localized: "minutes")
            )
            
        case .timeUnlock:
            DatePicker(
                String(localized: "Unlock Time"),
                selection: $unlockTime,
                displayedComponents: .hourAndMinute
            )
            .accessibilityIdentifier("unlockTimePicker")
            .onChange(of: unlockTime) { _, newTime in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                targetValue = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
        }
    }
    
    private func stepperControl(value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        HStack {
            Text("\(Int(value.wrappedValue)) \(unit)")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(goalType.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.numericText())
                .animation(.snappy, value: value.wrappedValue)
            
            Stepper(
                "",
                value: value,
                in: range,
                step: step
            )
            .labelsHidden()
            .accessibilityIdentifier("goalStepper.\(goalType.rawValue)")
        }
    }
    
    // MARK: - Computed Properties
    
    private var isValidInput: Bool {
        switch goalType {
        case .steps:
            return targetValue >= 1_000 && targetValue <= 50_000
        case .activeEnergy:
            return targetValue >= 50 && targetValue <= 2_000
        case .exercise:
            return targetValue >= 5 && targetValue <= 180
        case .timeUnlock:
            return true // Time is always valid
        }
    }
    
    // MARK: - Actions
    
    private func saveGoal() {
        isSaving = true
        
        Task {
            // Update exercise type if applicable
            if goalType == .exercise {
                viewModel.healthGoal.exerciseGoal.exerciseType = selectedExerciseType
            }
            
            await viewModel.addGoal(type: goalType, target: targetValue)
            triggerSuccessHaptic = true
            
            // Small delay to let haptic play before dismissing
            try? await Task.sleep(for: .milliseconds(150))
            dismiss()
        }
    }
}

// MARK: - Goal Type Extensions

extension GoalType {
    /// Hint text explaining the configuration for this goal type.
    var configurationHint: String {
        switch self {
        case .steps:
            return String(localized: "Set your daily step target. The average adult takes 4,000-10,000 steps per day.")
        case .activeEnergy:
            return String(localized: "Set your active calorie burn target. Most people burn 200-600 kcal during exercise.")
        case .exercise:
            return String(localized: "Set your daily exercise minutes. Health experts recommend at least 30 minutes of activity.")
        case .timeUnlock:
            return String(localized: "Apps will unlock at this time each day, regardless of other goals.")
        }
    }
}

// MARK: - Preview

#Preview("Steps Configuration") {
    NavigationStack {
        GoalConfigurationView(
            viewModel: DashboardViewModel(healthService: MockHealthService(), blockerService: MockBlockerService()),
            goalType: .steps
        )
    }
}

#Preview("Exercise Configuration") {
    NavigationStack {
        GoalConfigurationView(
            viewModel: DashboardViewModel(healthService: MockHealthService(), blockerService: MockBlockerService()),
            goalType: .exercise
        )
    }
}

#Preview("Time Unlock Configuration") {
    NavigationStack {
        GoalConfigurationView(
            viewModel: DashboardViewModel(healthService: MockHealthService(), blockerService: MockBlockerService()),
            goalType: .timeUnlock
        )
    }
}
