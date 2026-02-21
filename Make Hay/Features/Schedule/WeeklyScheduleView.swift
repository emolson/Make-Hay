//
//  WeeklyScheduleView.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/21/26.
//

import SwiftUI

/// The weekly schedule editor, presented as a sheet from the Dashboard toolbar.
///
/// **Why a sheet instead of a new tab?** The schedule is a power-user feature that edits
/// a configuration surface — editing, not daily interaction. Keeping the tab bar at 2 items
/// (Dashboard + Settings) avoids cluttering the primary navigation.
///
/// **Design:** Mirrors the iOS Sleep Schedule pattern — a 7-day list where tapping a day
/// navigates to that day's goal configuration.
struct WeeklyScheduleView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var viewModel: WeeklyScheduleViewModel

    // MARK: - Initialization

    init(viewModel: WeeklyScheduleViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List(viewModel.daySummaries) { summary in
                NavigationLink(value: summary) {
                    dayRow(for: summary)
                }
                .accessibilityIdentifier("scheduleDay.\(summary.weekday)")
            }
            .navigationTitle(String(localized: "Weekly Schedule"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("scheduleCloseButton")
                }
            }
            .navigationDestination(for: DaySummary.self) { summary in
                viewModel.destinationView(for: summary)
            }
        }
    }

    // MARK: - Row

    /// A single day row showing the weekday name, a "Today" badge when applicable,
    /// and a summary of enabled goals.
    @ViewBuilder
    private func dayRow(for summary: DaySummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(summary.name)
                        .font(.body)
                        .fontWeight(summary.isToday ? .semibold : .regular)

                    if summary.isToday {
                        Text(String(localized: "Today"))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.statusInfo.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.statusInfo)
                    }
                }

                Text(summary.goalSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if summary.goalCount > 0 {
                Text("\(summary.goalCount)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    WeeklyScheduleView(
        viewModel: WeeklyScheduleViewModel(
            dashboardViewModel: DashboardViewModel(
                healthService: MockHealthService(),
                blockerService: MockBlockerService()
            )
        )
    )
}
