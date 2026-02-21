//
//  DayGoalsView.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/21/26.
//

import SwiftUI

/// Displays and edits the goal configuration for a specific weekday.
///
/// **Why separate from DashboardView?** The Dashboard shows *today's* live progress
/// (current steps, calories, etc.). This view shows the *target configuration* for any
/// weekday — no live data, just what goals are set and their targets.
///
/// **Navigation:** Pushed from `WeeklyScheduleView` via `NavigationLink`.
/// Tapping a goal row opens `GoalConfigurationView` in edit mode with the correct weekday.
struct DayGoalsView: View {

    // MARK: - Properties

    /// The weekday (1–7) being configured.
    let weekday: Int

    /// Shared schedule manager (non-owned).
    let viewModel: any ScheduleGoalManaging

    // MARK: - State

    @State private var isShowingAddGoal: Bool = false
    @State private var editingGoalType: EditableGoal?

    // MARK: - Computed

    /// The `HealthGoal` for this weekday, read from the live schedule.
    private var dayGoal: HealthGoal {
        viewModel.weeklySchedule.goal(for: weekday)
    }

    /// Whether this is today's weekday.
    private var isToday: Bool {
        weekday == viewModel.todayWeekday
    }

    /// The day's full name (e.g. "Monday").
    private var dayName: String {
        WeeklyGoalSchedule.fullName(for: weekday)
    }

    /// Goal rows to display (similar to DashboardViewModel.goalProgresses but static targets).
    private var goalRows: [GoalRow] {
        var rows: [GoalRow] = []

        if dayGoal.stepGoal.isEnabled {
            rows.append(GoalRow(
                type: .steps,
                label: GoalType.steps.displayName,
                target: "\(dayGoal.stepGoal.target) steps",
                iconName: GoalType.steps.iconName,
                color: GoalType.steps.color,
                exerciseGoalId: nil,
                exerciseType: nil
            ))
        }

        if dayGoal.activeEnergyGoal.isEnabled {
            rows.append(GoalRow(
                type: .activeEnergy,
                label: GoalType.activeEnergy.displayName,
                target: "\(dayGoal.activeEnergyGoal.target) kcal",
                iconName: GoalType.activeEnergy.iconName,
                color: GoalType.activeEnergy.color,
                exerciseGoalId: nil,
                exerciseType: nil
            ))
        }

        for exerciseGoal in dayGoal.exerciseGoals where exerciseGoal.isEnabled {
            rows.append(GoalRow(
                type: .exercise,
                label: exerciseGoal.exerciseType.displayName,
                target: "\(exerciseGoal.targetMinutes) min",
                iconName: exerciseGoal.exerciseType.iconName,
                color: GoalType.exercise.color,
                exerciseGoalId: exerciseGoal.id,
                exerciseType: exerciseGoal.exerciseType
            ))
        }

        if dayGoal.timeBlockGoal.isEnabled {
            let unlockTime = dayGoal.timeBlockGoal.unlockDate()
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            rows.append(GoalRow(
                type: .timeUnlock,
                label: GoalType.timeUnlock.displayName,
                target: formatter.string(from: unlockTime),
                iconName: GoalType.timeUnlock.iconName,
                color: GoalType.timeUnlock.color,
                exerciseGoalId: nil,
                exerciseType: nil
            ))
        }

        return rows
    }

    /// Available goal types that haven't been added yet (exercise always available).
    private var availableGoalTypes: [GoalType] {
        GoalType.allCases.filter { type in
            switch type {
            case .exercise:
                return true
            default:
                return !goalRows.contains { $0.type == type }
            }
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            if goalRows.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(String(localized: "No Goals"), systemImage: "target")
                    } description: {
                        Text(String(localized: "Add a goal to configure this day."))
                    }
                }
            } else {
                Section {
                    ForEach(goalRows) { row in
                        Button {
                            editingGoalType = EditableGoal(
                                type: row.type,
                                exerciseGoalId: row.exerciseGoalId
                            )
                        } label: {
                            goalRowView(row)
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text(String(localized: "GOALS"))
                }

                // Blocking strategy
                Section {
                    Picker(String(localized: "Unlock when"), selection: Binding(
                        get: { dayGoal.blockingStrategy },
                        set: { newValue in
                            Task {
                                await viewModel.updateBlockingStrategy(
                                    newValue,
                                    forWeekday: weekday
                                )
                            }
                        }
                    )) {
                        ForEach(BlockingStrategy.allCases) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("dayBlockingStrategyPicker")
                } header: {
                    Text(String(localized: "UNLOCK WHEN"))
                }
            }

            // Pending change indicator
            if dayGoal.pendingGoal != nil {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(Color.statusInfo)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Change Scheduled"))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if let date = dayGoal.pendingGoalEffectiveDate {
                                Text("Takes effect \(date, style: .date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // Add goal button
            if !availableGoalTypes.isEmpty {
                Section {
                    Button {
                        isShowingAddGoal = true
                    } label: {
                        Label(String(localized: "Add Goal"), systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("dayAddGoalButton")
                }
            }
        }
        .navigationTitle(dayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingAddGoal) {
            NavigationStack {
                DayAddGoalView(
                    weekday: weekday,
                    viewModel: viewModel,
                    availableGoalTypes: availableGoalTypes
                )
            }
        }
        .sheet(item: $editingGoalType) { editable in
            editGoalSheet(for: editable)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func goalRowView(_ row: GoalRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.iconName)
                .font(.title3)
                .foregroundStyle(row.color)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.label)
                    .font(.body)
                Text(row.target)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Edit Sheet

    @ViewBuilder
    private func editGoalSheet(for editable: EditableGoal) -> some View {
        let exerciseGoal: ExerciseGoal? = {
            if editable.type == .exercise, let id = editable.exerciseGoalId {
                return dayGoal.exerciseGoals.first { $0.id == id }
            }
            return nil
        }()

        NavigationStack {
            GoalConfigurationView(
                viewModel: viewModel,
                goalType: editable.type,
                mode: .edit(exerciseGoalId: editable.exerciseGoalId),
                exerciseGoal: exerciseGoal,
                weekday: weekday
            )
        }
    }
}

// MARK: - Supporting Types

/// A row in the goal list (static target display, no live data).
private struct GoalRow: Identifiable {
    let type: GoalType
    let label: String
    let target: String
    let iconName: String
    let color: Color
    let exerciseGoalId: UUID?
    let exerciseType: ExerciseType?

    var id: String {
        if let exerciseGoalId {
            return "\(type.rawValue)_\(exerciseGoalId.uuidString)"
        }
        return type.rawValue
    }
}

/// Identifiable wrapper for the goal being edited, used with `.sheet(item:)`.
private struct EditableGoal: Identifiable {
    let type: GoalType
    let exerciseGoalId: UUID?

    var id: String {
        if let exerciseGoalId {
            return "\(type.rawValue)_\(exerciseGoalId.uuidString)"
        }
        return type.rawValue
    }
}

// MARK: - Day Add Goal View

/// Simplified version of `AddGoalView` that routes to `GoalConfigurationView`
/// with the correct weekday parameter.
private struct DayAddGoalView: View {
    @Environment(\.dismiss) private var dismiss
    let weekday: Int
    let viewModel: any ScheduleGoalManaging
    let availableGoalTypes: [GoalType]

    @State private var selectedGoalType: GoalType?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(availableGoalTypes) { goalType in
                    Button {
                        selectedGoalType = goalType
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: goalType.iconName)
                                .font(.title2)
                                .foregroundStyle(goalType.color)
                                .frame(width: 44, height: 44)
                                .background(goalType.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(goalType.displayName)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(goalType.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding()
                        .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .tint(.primary)
                }
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
                goalType: goalType,
                mode: .add,
                weekday: weekday
            )
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DayGoalsView(
            weekday: Calendar.current.component(.weekday, from: Date()),
            viewModel: DashboardViewModel(
                healthService: MockHealthService(),
                blockerService: MockBlockerService()
            )
        )
    }
}
