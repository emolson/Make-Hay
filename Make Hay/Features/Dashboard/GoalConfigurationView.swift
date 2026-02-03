//
//  GoalConfigurationView.swift
//  Make Hay
//
//  Created by Ethan Olson on 1/30/26.
//

import SwiftUI

/// Represents the mode of the GoalConfigurationView.
/// **Why an enum?** Distinguishes between adding a new goal and editing an existing one,
/// allowing the view to adapt its UI (button labels, remove option) accordingly.
enum GoalConfigurationMode: Equatable {
    case add
    case edit(exerciseGoalId: UUID?)
    
    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }
    
    var exerciseGoalId: UUID? {
        if case .edit(let id) = self { return id }
        return nil
    }
}

/// View for configuring a specific goal type's target value.
/// Supports both adding new goals and editing existing ones.
///
/// **Why separate configuration view?** Each goal type has different units and constraints
/// (steps vs. calories vs. time). This view adapts its interface based on the goal type.
struct GoalConfigurationView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var viewModel: DashboardViewModel
    let goalType: GoalType
    let mode: GoalConfigurationMode
    
    @State private var targetValue: Double
    @State private var selectedExerciseType: ExerciseType = .any
    @State private var unlockTime: Date
    @State private var isSaving: Bool = false
    @State private var triggerSuccessHaptic: Bool = false
    @State private var showingRemoveConfirmation: Bool = false
    
    // MARK: - Initialization
    
    /// Creates a GoalConfigurationView for adding a new goal.
    /// Pre-fills with existing values if the goal was previously configured.
    /// - Parameters:
    ///   - viewModel: The ViewModel managing dashboard state.
    ///   - goalType: The type of goal being configured.
    init(viewModel: DashboardViewModel, goalType: GoalType) {
        self.init(viewModel: viewModel, goalType: goalType, mode: .add)
    }
    
    /// Creates a GoalConfigurationView for adding or editing a goal.
    /// - Parameters:
    ///   - viewModel: The ViewModel managing dashboard state.
    ///   - goalType: The type of goal being configured.
    ///   - mode: Whether adding a new goal or editing an existing one.
    ///   - exerciseGoal: The specific exercise goal being edited (for exercise goals only).
    init(viewModel: DashboardViewModel, goalType: GoalType, mode: GoalConfigurationMode, exerciseGoal: ExerciseGoal? = nil) {
        _viewModel = State(initialValue: viewModel)
        self.goalType = goalType
        self.mode = mode
        
        // Initialize unlockTime with a default (only used for .timeUnlock goals)
        let defaultUnlockTime = viewModel.healthGoal.timeBlockGoal.unlockDate()
        _unlockTime = State(initialValue: defaultUnlockTime)
        
        // Pre-fill based on mode
        switch goalType {
        case .steps:
            _targetValue = State(initialValue: Double(viewModel.healthGoal.stepGoal.target))
        case .activeEnergy:
            _targetValue = State(initialValue: Double(viewModel.healthGoal.activeEnergyGoal.target))
        case .exercise:
            if let exerciseGoal {
                // Editing a specific exercise goal
                _targetValue = State(initialValue: Double(exerciseGoal.targetMinutes))
                _selectedExerciseType = State(initialValue: exerciseGoal.exerciseType)
            } else if let lastExerciseGoal = viewModel.healthGoal.exerciseGoals.last {
                // Adding new - use last exercise goal as template
                _targetValue = State(initialValue: Double(lastExerciseGoal.targetMinutes))
                _selectedExerciseType = State(initialValue: lastExerciseGoal.exerciseType)
            } else {
                // Default for first exercise goal
                _targetValue = State(initialValue: 30)
                _selectedExerciseType = State(initialValue: .any)
            }
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
            
            // Remove goal section (only shown in edit mode)
            if mode.isEditing {
                Section {
                    Button(role: .destructive) {
                        showingRemoveConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text(String(localized: "Remove Goal"))
                            Spacer()
                        }
                    }
                    .accessibilityIdentifier("removeGoalButton")
                }
            }
        }
        .navigationTitle(mode.isEditing ? String(localized: "Edit Goal") : goalType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                        .accessibilityIdentifier("savingIndicator")
                } else {
                    Button(mode.isEditing ? String(localized: "Save") : String(localized: "Add")) {
                        saveGoal()
                    }
                    .disabled(!isValidInput)
                    .accessibilityIdentifier(mode.isEditing ? "saveGoalButton" : "addGoalConfirmButton")
                }
            }
            
            if mode.isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("cancelEditButton")
                }
            }
        }
        .disabled(isSaving)
        .sensoryFeedback(.success, trigger: triggerSuccessHaptic)
        .confirmationDialog(
            String(localized: "Remove Goal"),
            isPresented: $showingRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Remove"), role: .destructive) {
                removeGoal()
            }
            Button(String(localized: "Cancel"), role: .cancel) { }
        } message: {
            Text(String(localized: "Are you sure you want to remove this goal? This cannot be undone."))
        }
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
            if mode.isEditing {
                // Update existing goal
                await viewModel.updateGoal(
                    type: goalType,
                    target: targetValue,
                    exerciseGoalId: mode.exerciseGoalId,
                    exerciseType: selectedExerciseType
                )
            } else {
                // Add new goal
                await viewModel.addGoal(type: goalType, target: targetValue, exerciseType: selectedExerciseType)
            }
            
            triggerSuccessHaptic = true
            
            // Small delay to let haptic play before dismissing
            try? await Task.sleep(for: .milliseconds(150))
            dismiss()
        }
    }
    
    private func removeGoal() {
        Task {
            await viewModel.removeGoal(type: goalType, exerciseGoalId: mode.exerciseGoalId)
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

#Preview("Steps Configuration - Add") {
    NavigationStack {
        GoalConfigurationView(
            viewModel: DashboardViewModel(healthService: MockHealthService(), blockerService: MockBlockerService()),
            goalType: .steps
        )
    }
}

#Preview("Steps Configuration - Edit") {
    NavigationStack {
        GoalConfigurationView(
            viewModel: DashboardViewModel(healthService: MockHealthService(), blockerService: MockBlockerService()),
            goalType: .steps,
            mode: .edit(exerciseGoalId: nil)
        )
    }
}

#Preview("Exercise Configuration - Add") {
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
