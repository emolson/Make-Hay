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

/// Identifiable wrapper for a proposed `HealthGoal` used with `.sheet(item:)`.
///
/// **Why a wrapper?** `HealthGoal` is a value type without a stable identity.
/// `.sheet(item:)` requires `Identifiable`, and a lightweight wrapper avoids
/// polluting the model layer with presentation concerns.
private struct PendingGoalProposal: Identifiable {
    let id = UUID()
    let goal: HealthGoal
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
    
    /// Non-owned reference to the shared goal manager.
    /// **Why `let` instead of `@State`?** This view does not own the ViewModel — it is
    /// created by `DashboardView` and passed in. Using `@State` for a non-owned
    /// `@Observable` reference can cause lifecycle issues where the first `Task`
    /// capture receives a stale wrapper, bypassing the gate on initial presentation.
    let viewModel: any ScheduleGoalManaging
    let goalType: GoalType
    let mode: GoalConfigurationMode

    /// The weekday (1–7) this configuration targets.
    /// Defaults to `todayWeekday` for Dashboard edits; set explicitly for schedule edits.
    ///
    /// **Why a stored property?** Future-day edits skip the deferral gate and route to
    /// weekday-aware ViewModel methods, so the view needs to know which day it's editing.
    let weekday: Int
    
    @State private var targetValue: Double
    @State private var selectedExerciseType: ExerciseType = .any
    @State private var unlockTime: Date
    @State private var isSaving: Bool = false
    @State private var triggerSuccessHaptic: Bool = false
    @State private var showingRemoveConfirmation: Bool = false

    /// Wrapper tying a proposed goal to `.sheet(item:)` presentation.
    ///
    /// **Why not separate `Bool` + `Optional`?** `.sheet(isPresented:)` can render
    /// its content before a companion `@State` optional is set, causing a blank
    /// sheet on first presentation. `.sheet(item:)` guarantees the data is
    /// available when the sheet content closure runs.
    @State private var pendingProposal: PendingGoalProposal?

    /// Whether this view is editing today's goal (and therefore subject to deferral rules).
    private var isEditingToday: Bool { weekday == viewModel.todayWeekday }
    
    // MARK: - Initialization
    
    /// Creates a GoalConfigurationView for adding a new goal (today).
    /// Pre-fills with existing values if the goal was previously configured.
    /// - Parameters:
    ///   - viewModel: The ViewModel managing dashboard state.
    ///   - goalType: The type of goal being configured.
    init(viewModel: any ScheduleGoalManaging, goalType: GoalType) {
        self.init(viewModel: viewModel, goalType: goalType, mode: .add, weekday: viewModel.todayWeekday)
    }
    
    /// Creates a GoalConfigurationView for adding or editing a goal.
    /// - Parameters:
    ///   - viewModel: The ViewModel managing dashboard state.
    ///   - goalType: The type of goal being configured.
    ///   - mode: Whether adding a new goal or editing an existing one.
    ///   - exerciseGoal: The specific exercise goal being edited (for exercise goals only).
    ///   - weekday: The weekday this edit targets (1–7). Defaults to today.
    init(
        viewModel: any ScheduleGoalManaging,
        goalType: GoalType,
        mode: GoalConfigurationMode,
        exerciseGoal: ExerciseGoal? = nil,
        weekday: Int? = nil
    ) {
        self.viewModel = viewModel
        self.goalType = goalType
        self.mode = mode
        self.weekday = weekday ?? viewModel.todayWeekday

        // Resolve the goal for the target weekday (may differ from today)
        let dayGoal = viewModel.weeklySchedule.goal(for: self.weekday)
        
        // Initialize unlockTime with a default (only used for .timeUnlock goals)
        let defaultUnlockTime = dayGoal.timeBlockGoal.unlockDate()
        _unlockTime = State(initialValue: defaultUnlockTime)
        
        // Pre-fill based on mode
        switch goalType {
        case .steps:
            _targetValue = State(initialValue: Double(dayGoal.stepGoal.target))
        case .activeEnergy:
            _targetValue = State(initialValue: Double(dayGoal.activeEnergyGoal.target))
        case .exercise:
            if let exerciseGoal {
                // Editing a specific exercise goal
                _targetValue = State(initialValue: Double(exerciseGoal.targetMinutes))
                _selectedExerciseType = State(initialValue: exerciseGoal.exerciseType)
            } else if let lastExerciseGoal = dayGoal.exerciseGoals.last {
                // Adding new - use last exercise goal as template
                _targetValue = State(initialValue: Double(lastExerciseGoal.targetMinutes))
                _selectedExerciseType = State(initialValue: lastExerciseGoal.exerciseType)
            } else {
                // Default for first exercise goal
                _targetValue = State(initialValue: 30)
                _selectedExerciseType = State(initialValue: .any)
            }
        case .timeUnlock:
            _targetValue = State(initialValue: Double(dayGoal.timeBlockGoal.unlockTimeMinutes))
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
        .sheet(item: $pendingProposal) { proposal in
            PendingGoalChangeView(
                context: .goalChange(
                    targetDayName: WeeklyGoalSchedule.fullName(for: weekday)
                )
            ) {
                // Schedule for next occurrence of this weekday
                viewModel.schedulePendingGoal(proposal.goal, forWeekday: weekday)
                dismiss()
            } onEmergencyUnlock: {
                // Apply immediately via emergency unlock
                Task {
                    await viewModel.applyEmergencyChange(proposal.goal)
                    triggerSuccessHaptic = true
                    try? await Task.sleep(for: .milliseconds(150))
                    dismiss()
                }
            }
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
            // Build the proposed goal configuration from the target weekday's goal
            let currentDayGoal = viewModel.weeklySchedule.goal(for: weekday)
            var newGoal = currentDayGoal
            
            if mode.isEditing {
                // Update existing goal
                switch goalType {
                case .steps:
                    newGoal.stepGoal.target = Int(targetValue)
                case .activeEnergy:
                    newGoal.activeEnergyGoal.target = Int(targetValue)
                case .exercise:
                    if let exerciseGoalId = mode.exerciseGoalId,
                       let index = newGoal.exerciseGoals.firstIndex(where: { $0.id == exerciseGoalId }) {
                        newGoal.exerciseGoals[index].targetMinutes = Int(targetValue)
                        newGoal.exerciseGoals[index].exerciseType = selectedExerciseType
                    }
                case .timeUnlock:
                    newGoal.timeBlockGoal.unlockTimeMinutes = Int(targetValue)
                }
            } else {
                // Add new goal
                switch goalType {
                case .steps:
                    newGoal.stepGoal.isEnabled = true
                    newGoal.stepGoal.target = Int(targetValue)
                case .activeEnergy:
                    newGoal.activeEnergyGoal.isEnabled = true
                    newGoal.activeEnergyGoal.target = Int(targetValue)
                case .exercise:
                    let newExerciseGoal = ExerciseGoal(
                        isEnabled: true,
                        targetMinutes: Int(targetValue),
                        exerciseType: selectedExerciseType
                    )
                    newGoal.exerciseGoals.append(newExerciseGoal)
                case .timeUnlock:
                    newGoal.timeBlockGoal.isEnabled = true
                    newGoal.timeBlockGoal.unlockTimeMinutes = Int(targetValue)
                }
            }
            
            // Determine the intent of this change
            let intent = GoalChangeIntent.determine(original: currentDayGoal, proposed: newGoal)

            // Only defer edits when editing today — future days aren't actively blocking
            let shouldDefer: Bool
            if isEditingToday && intent == .easier {
                shouldDefer = await viewModel.shouldDeferGoalEdits()
            } else {
                shouldDefer = false
            }
            
            // If making goal easier while apps are blocked, show confirmation
            if shouldDefer {
                pendingProposal = PendingGoalProposal(goal: newGoal)
                isSaving = false
            } else {
                // Apply immediately for harder goals, future days, or when not blocking
                if mode.isEditing {
                    await viewModel.updateGoal(
                        type: goalType,
                        target: targetValue,
                        exerciseGoalId: mode.exerciseGoalId,
                        exerciseType: selectedExerciseType,
                        forWeekday: weekday
                    )
                } else {
                    await viewModel.addGoal(
                        type: goalType,
                        target: targetValue,
                        exerciseType: selectedExerciseType,
                        forWeekday: weekday
                    )
                }
                
                triggerSuccessHaptic = true
                
                // Small delay to let haptic play before dismissing
                try? await Task.sleep(for: .milliseconds(150))
                dismiss()
            }
        }
    }
    
    private func removeGoal() {
        Task {
            isSaving = true
            defer { isSaving = false }

            // Build the proposed goal configuration with the goal removed
            let currentDayGoal = viewModel.weeklySchedule.goal(for: weekday)
            var newGoal = currentDayGoal
            switch goalType {
            case .steps:
                newGoal.stepGoal.isEnabled = false
            case .activeEnergy:
                newGoal.activeEnergyGoal.isEnabled = false
            case .exercise:
                if let exerciseGoalId = mode.exerciseGoalId {
                    newGoal.exerciseGoals.removeAll { $0.id == exerciseGoalId }
                }
            case .timeUnlock:
                newGoal.timeBlockGoal.isEnabled = false
            }
            
            // Determine intent (removal is always "easier")
            let intent = GoalChangeIntent.determine(original: currentDayGoal, proposed: newGoal)

            // Only defer when editing today
            let shouldDefer: Bool
            if isEditingToday && intent == .easier {
                shouldDefer = await viewModel.shouldDeferGoalEdits()
            } else {
                shouldDefer = false
            }
            
            // If removing while blocked on today, schedule or require emergency override
            if shouldDefer {
                pendingProposal = PendingGoalProposal(goal: newGoal)
            } else {
                await viewModel.removeGoal(
                    type: goalType,
                    exerciseGoalId: mode.exerciseGoalId,
                    forWeekday: weekday
                )
                dismiss()
            }
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
