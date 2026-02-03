//
//  AddGoalView.swift
//  Make Hay
//
//  Created by Ethan Olson on 1/30/26.
//

import SwiftUI

/// View for selecting and configuring a new health goal.
/// Presents available goal types and navigates to configuration screens.
///
/// **Why a NavigationStack here?** The add goal flow is multi-step (select type → configure),
/// so we use NavigationStack within the sheet to enable forward navigation.
struct AddGoalView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    @State private var viewModel: DashboardViewModel
    @State private var selectedGoalType: GoalType?
    
    // MARK: - Initialization
    
    /// Creates an AddGoalView with the specified ViewModel.
    /// - Parameter viewModel: The ViewModel managing dashboard state.
    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    
                    goalTypesGrid
                }
                .padding()
            }
            .navigationTitle(String(localized: "Add Goal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
            }
            .navigationDestination(item: $selectedGoalType) { goalType in
                GoalConfigurationView(
                    viewModel: viewModel,
                    goalType: goalType
                )
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 50))
                .foregroundStyle(.secondary)
            
            Text(String(localized: "Choose a Goal Type"))
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(String(localized: "Track your progress and unlock apps when you reach your goals"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top)
    }
    
    @ViewBuilder
    private var goalTypesGrid: some View {
        if viewModel.availableGoalTypes.isEmpty {
            allGoalsAddedView
        } else {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(viewModel.availableGoalTypes) { goalType in
                    GoalTypeCard(goalType: goalType) {
                        selectedGoalType = goalType
                    }
                }
            }
        }
    }
    
    private var allGoalsAddedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            
            Text(String(localized: "All Goals Added!"))
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(String(localized: "You've added all available goal types. You can edit or remove goals from the dashboard."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button(String(localized: "Done")) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding()
        .accessibilityIdentifier("allGoalsAddedView")
    }
}

// MARK: - Goal Type Card

/// A card representing a selectable goal type.
private struct GoalTypeCard: View {
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

// MARK: - Goal Type Extensions

extension GoalType {
    /// A brief description of what the goal tracks.
    var description: String {
        switch self {
        case .steps:
            return String(localized: "Track daily steps")
        case .activeEnergy:
            return String(localized: "Track calories burned")
        case .exercise:
            return String(localized: "Track workout time")
        case .timeUnlock:
            return String(localized: "Unlock at a time")
        }
    }
}

// MARK: - Preview

#Preview("With Available Goals") {
    AddGoalView(viewModel: makeAvailableGoalsPreviewViewModel())
}

#Preview("All Goals Added") {
    AddGoalView(viewModel: makeAllGoalsPreviewViewModel())
}

private func makeAvailableGoalsPreviewViewModel() -> DashboardViewModel {
    let mock = MockHealthService()
    let viewModel = DashboardViewModel(healthService: mock, blockerService: MockBlockerService())
    // Disable some goals to make them available to add
    viewModel.healthGoal.activeEnergyGoal.isEnabled = false
    viewModel.healthGoal.exerciseGoals.removeAll()
    viewModel.healthGoal.timeBlockGoal.isEnabled = false
    return viewModel
}

private func makeAllGoalsPreviewViewModel() -> DashboardViewModel {
    let mock = MockHealthService()
    let viewModel = DashboardViewModel(healthService: mock, blockerService: MockBlockerService())
    // Enable all goals
    viewModel.healthGoal.stepGoal.isEnabled = true
    viewModel.healthGoal.activeEnergyGoal.isEnabled = true
    viewModel.healthGoal.exerciseGoals = [ExerciseGoal(isEnabled: true, targetMinutes: 30, exerciseType: .any)]
    viewModel.healthGoal.timeBlockGoal.isEnabled = true
    return viewModel
}
