//
//  SettingsView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI

/// The settings view where users can configure their goals and app preferences.
///
/// **Why use @AppStorage?** This provides automatic persistence to UserDefaults,
/// ensuring the user's goal preference survives app restarts without requiring
/// a dedicated persistence layer for simple key-value data.
struct SettingsView: View {
    
    // MARK: - State
    
    /// The user's daily step goal, persisted to UserDefaults.
    /// Defaults to 10,000 steps, a commonly recommended daily target.
    @AppStorage("dailyStepGoal") private var dailyStepGoal: Int = 10_000
    
    /// The minimum step goal allowed.
    private let minimumGoal: Int = 1_000
    
    /// The maximum step goal allowed.
    private let maximumGoal: Int = 50_000
    
    /// The increment/decrement step size for the stepper.
    private let stepIncrement: Int = 500
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            List {
                goalSection
                blockedAppsSection
            }
            .navigationTitle(String(localized: "Settings"))
        }
    }
    
    // MARK: - Sections
    
    private var goalSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "figure.walk")
                        .foregroundStyle(.tint)
                        .font(.title2)
                    
                    Text(String(localized: "Daily Step Goal"))
                        .font(.headline)
                }
                
                Text(formattedGoal)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("currentGoalLabel")
                
                Stepper(
                    value: $dailyStepGoal,
                    in: minimumGoal...maximumGoal,
                    step: stepIncrement
                ) {
                    Text(String(localized: "Adjust by \(stepIncrement.formatted())"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("stepGoalStepper")
            }
            .padding(.vertical, 8)
        } header: {
            Text(String(localized: "Goals"))
        } footer: {
            Text(String(localized: "Set your daily step target. Apps will be blocked until you reach this goal."))
        }
    }
    
    private var blockedAppsSection: some View {
        Section {
            HStack {
                Image(systemName: "app.badge")
                    .foregroundStyle(.tint)
                Text(String(localized: "App selection will appear here."))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "Blocked Apps"))
        }
    }
    
    // MARK: - Computed Properties
    
    /// Formats the step goal with thousands separator for display.
    private var formattedGoal: String {
        dailyStepGoal.formatted(.number)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
}
