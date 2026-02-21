//
//  GoalProgressRowView.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/21/26.
//

import SwiftUI

/// A single row displaying one goal's progress as a labeled linear bar.
///
/// **Why a dedicated view?** Isolates formatting, accessibility, and layout
/// for each goal into a self-contained struct, keeping `DashboardView` lean.
/// Uses SwiftUI's native `Gauge` so accessibility traits (percentage readout,
/// value labels) are provided automatically without custom VoiceOver wiring.
struct GoalProgressRowView: View {

    let progress: GoalProgress
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                headerRow
                progressGauge
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("goalProgressRow.\(progress.id)")
        .accessibilityHint(String(localized: "Tap to edit goal"))
    }

    // MARK: - Subviews

    /// Icon, title, exercise sub-label, current/target text, and chevron.
    private var headerRow: some View {
        HStack(spacing: 8) {
            goalIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(progress.type.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                if let exerciseType = progress.exerciseType, exerciseType != .any {
                    Text(exerciseType.displayName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text("\(formattedCurrentValue(includeUnit: true)) / \(formattedTargetValue())")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// Shows the goal icon with a green checkmark overlay when met.
    private var goalIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: progress.exerciseType?.iconName ?? progress.type.iconName)
                .font(.subheadline)
                .foregroundStyle(progress.isMet ? Color.statusSuccess : progress.type.color)
                .frame(width: 24, height: 24, alignment: .center)

            if progress.isMet {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.statusSuccess)
                    .offset(x: 4, y: 4)
            }
        }
    }

    /// Native linear gauge showing 0→1 progress, tinted to the goal color.
    private var progressGauge: some View {
        Gauge(value: progress.progress, in: 0...1) {
            EmptyView()
        }
        .gaugeStyle(.linearCapacity)
        .tint(progress.isMet ? Color.statusSuccess : progress.type.color)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress.progress)
    }

    // MARK: - Formatting Helpers

    /// Formats the current value for display.
    /// - Parameter includeUnit: Whether to append the unit label (e.g. "steps").
    private func formattedCurrentValue(includeUnit: Bool) -> String {
        switch progress.type {
        case .steps:
            let formatted = Int(progress.current).formatted(.number)
            return includeUnit ? localizedStepsValue(formatted) : formatted
        case .activeEnergy:
            return localizedKilocaloriesValue(Int(progress.current))
        case .exercise:
            return localizedMinutesValue(Int(progress.current))
        case .timeUnlock:
            return formattedTimeValue(minutesSinceMidnight: Int(progress.current))
        }
    }

    /// Formats the target value for display (always includes unit).
    private func formattedTargetValue() -> String {
        switch progress.type {
        case .steps:
            return localizedStepsValue(Int(progress.target).formatted(.number))
        case .activeEnergy:
            return localizedKilocaloriesValue(Int(progress.target))
        case .exercise:
            return localizedMinutesValue(Int(progress.target))
        case .timeUnlock:
            return formattedTimeValue(minutesSinceMidnight: Int(progress.target))
        }
    }

    private func localizedStepsValue(_ formattedValue: String) -> String {
        String(
            localized: "dashboard.units.steps",
            defaultValue: "\(formattedValue) steps",
            comment: "Steps value with unit"
        )
    }

    private func localizedKilocaloriesValue(_ value: Int) -> String {
        let formatted = value.formatted(.number)
        return String(
            localized: "dashboard.units.kilocalories",
            defaultValue: "\(formatted) kcal",
            comment: "Active energy value in kilocalories"
        )
    }

    private func localizedMinutesValue(_ value: Int) -> String {
        let formatted = value.formatted(.number)
        return String(
            localized: "dashboard.units.minutes",
            defaultValue: "\(formatted) min",
            comment: "Exercise minutes value with unit"
        )
    }

    private func formattedTimeValue(minutesSinceMidnight: Int) -> String {
        let clamped = min(max(minutesSinceMidnight, 0), (24 * 60) - 1)
        let hour = clamped / 60
        let minute = clamped % 60
        let date = Calendar.current.date(
            bySettingHour: hour, minute: minute, second: 0, of: Date()
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Preview

#Preview("Steps – In Progress") {
    GoalProgressRowView(
        progress: GoalProgress(
            type: .steps,
            current: 4_500,
            target: 10_000,
            progress: 0.45,
            isMet: false,
            exerciseGoalId: nil,
            exerciseType: nil
        ),
        onTap: {}
    )
    .padding()
}

#Preview("Active Energy – Met") {
    GoalProgressRowView(
        progress: GoalProgress(
            type: .activeEnergy,
            current: 500,
            target: 500,
            progress: 1.0,
            isMet: true,
            exerciseGoalId: nil,
            exerciseType: nil
        ),
        onTap: {}
    )
    .padding()
}
