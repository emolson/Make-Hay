//
//  WeeklyScheduleViewModel.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/21/26.
//

import Foundation
import SwiftUI

/// Summary of a single weekday's goal configuration for list display.
///
/// **Why a separate struct?** Keeps the view layer decoupled from the full `HealthGoal`
/// model. Only the data needed for display is exposed, and the `weekday` index is
/// preserved for navigation.
struct DaySummary: Identifiable, Sendable {
    let weekday: Int             // Calendar.weekday: 1–7
    let name: String             // e.g. "Monday"
    let shortName: String        // e.g. "Mon"
    let goalSummary: String      // e.g. "Steps · Active Energy"
    let goalCount: Int           // Number of enabled goals
    let isToday: Bool

    var id: Int { weekday }
}

/// ViewModel for the weekly schedule editor.
///
/// **Why @Observable @MainActor?** The schedule list is a UI concern. By isolating to
/// the main actor and using `@Observable`, SwiftUI reactively updates when the
/// underlying schedule manager's `weeklySchedule` changes.
@Observable
@MainActor
final class WeeklyScheduleViewModel {

    // MARK: - Dependencies

    /// Reference to the shared schedule manager that owns the weekly goals.
    let dashboardViewModel: any ScheduleGoalManaging

    // MARK: - Initialization

    init(dashboardViewModel: any ScheduleGoalManaging) {
        self.dashboardViewModel = dashboardViewModel
    }

    // MARK: - Computed State

    /// Ordered day summaries starting from the user's locale-preferred first weekday.
    var daySummaries: [DaySummary] {
        let orderedWeekdays = WeeklyGoalSchedule.orderedWeekdays()
        let todayWeekday = dashboardViewModel.todayWeekday

        return orderedWeekdays.map { weekday in
            let goal = dashboardViewModel.weeklySchedule.goal(for: weekday)
            return DaySummary(
                weekday: weekday,
                name: WeeklyGoalSchedule.fullName(for: weekday),
                shortName: WeeklyGoalSchedule.shortName(for: weekday),
                goalSummary: goalSummaryText(for: goal),
                goalCount: enabledGoalCount(for: goal),
                isToday: weekday == todayWeekday
            )
        }
    }

    // MARK: - Helpers

    /// Returns a human-readable summary of enabled goals (e.g. "Steps · Active Energy · 2 Exercise").
    private func goalSummaryText(for goal: HealthGoal) -> String {
        var parts: [String] = []

        if goal.stepGoal.isEnabled {
            parts.append(String(localized: "Steps"))
        }
        if goal.activeEnergyGoal.isEnabled {
            parts.append(String(localized: "Active Energy"))
        }

        let enabledExercise = goal.exerciseGoals.filter(\.isEnabled)
        if enabledExercise.count == 1, let first = enabledExercise.first {
            parts.append(first.exerciseType.displayName)
        } else if enabledExercise.count > 1 {
            parts.append(String(localized: "\(enabledExercise.count) Exercise"))
        }

        if goal.timeBlockGoal.isEnabled {
            parts.append(String(localized: "Time"))
        }

        return parts.isEmpty
            ? String(localized: "No goals set")
            : parts.joined(separator: " · ")
    }

    /// Returns the number of enabled goals for a given day.
    private func enabledGoalCount(for goal: HealthGoal) -> Int {
        var count = 0
        if goal.stepGoal.isEnabled { count += 1 }
        if goal.activeEnergyGoal.isEnabled { count += 1 }
        count += goal.exerciseGoals.filter(\.isEnabled).count
        if goal.timeBlockGoal.isEnabled { count += 1 }
        return count
    }

    /// Builds the destination view for a weekday summary.
    ///
    /// **Why here?** Keeps routing decisions out of `WeeklyScheduleView`, which remains
    /// a pure rendering layer with no destination-construction logic.
    @ViewBuilder
    func destinationView(for summary: DaySummary) -> some View {
        DayGoalsView(
            weekday: summary.weekday,
            viewModel: dashboardViewModel
        )
    }
}
