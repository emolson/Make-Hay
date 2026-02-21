//
//  PendingGoalChangeView.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/3/26.
//

import SwiftUI

/// Context describing which guarded change flow is being confirmed.
enum PendingChangeContext {
    /// A goal is being made easier. The associated `targetDayName` is the full weekday
    /// name (e.g. "Monday") so the UI can say "Schedule for next Monday".
    case goalChange(targetDayName: String? = nil)
    case blockedAppsChange

    var navigationTitle: String {
        switch self {
        case .goalChange:
            return String(localized: "Update Goal?")
        case .blockedAppsChange:
            return String(localized: "Update Blocked Apps?")
        }
    }

    var headline: String {
        switch self {
        case .goalChange:
            return String(localized: "Preserve Your Momentum")
        case .blockedAppsChange:
            return String(localized: "Keep Your Guardrails Intact")
        }
    }

    var message: String {
        switch self {
        case .goalChange(let dayName):
            if let dayName {
                return String(localized: "You are lowering your target. To preserve your momentum, this change will take effect next \(dayName).")
            }
            return String(localized: "You are lowering your target. To preserve your momentum, this change will take effect tomorrow morning.")
        case .blockedAppsChange:
            return String(localized: "Your goals are not met yet. To preserve your commitment, blocked-app changes will take effect tomorrow morning.")
        }
    }

    var bulletPoints: [String] {
        switch self {
        case .goalChange(let dayName):
            let effectLabel = dayName.map { String(localized: "New target starts next \($0)") }
                ?? String(localized: "New target starts tomorrow at midnight")
            return [
                String(localized: "Today's target remains unchanged"),
                effectLabel,
                String(localized: "Your progress streak continues")
            ]
        case .blockedAppsChange:
            return [
                String(localized: "Today's blocking stays in place"),
                String(localized: "New app selection starts tomorrow at midnight"),
                String(localized: "Your goal guardrails stay consistent")
            ]
        }
    }

    /// Button label for the primary (schedule) action.
    var scheduleButtonLabel: String {
        switch self {
        case .goalChange(let dayName):
            if let dayName {
                return String(localized: "Schedule for Next \(dayName)")
            }
            return String(localized: "Schedule for Tomorrow")
        case .blockedAppsChange:
            return String(localized: "Schedule for Tomorrow")
        }
    }

    var emergencyWarningDescription: String {
        switch self {
        case .goalChange:
            return String(localized: "Emergency unlocks forfeit today's progress. This change will take effect immediately.")
        case .blockedAppsChange:
            return String(localized: "Emergency unlock applies your blocked-app changes immediately, even before goals are met.")
        }
    }
}

/// Modal view presented when a user attempts to lower their goal while apps are blocked.
/// Implements the "Next-Day Effect" by offering to schedule the change for tomorrow,
/// removing the immediate gratification of cheating.
///
/// **Why this works:** If lowering the goal doesn't unlock apps now, there's no incentive
/// to cheat in a moment of weakness. The user can still adjust goals, but only for tomorrow.
struct PendingGoalChangeView: View {
    
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - State
    
    /// Tracks whether to show the emergency unlock flow.
    @State private var showingEmergencyUnlock: Bool = false

    /// The guarded flow context that controls copy/content.
    let context: PendingChangeContext
    
    /// Callback invoked when the user chooses to schedule the change for tomorrow.
    let onSchedule: () -> Void
    
    /// Callback invoked when the user confirms an emergency unlock.
    let onEmergencyUnlock: () -> Void
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                
                headerIcon
                
                messageContent
                
                Spacer()
                
                actionButtons
            }
            .padding()
            .navigationTitle(context.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("cancelGoalChangeButton")
                }
            }
            .sheet(isPresented: $showingEmergencyUnlock) {
                EmergencyUnlockView(
                    warningDescription: context.emergencyWarningDescription
                ) {
                    onEmergencyUnlock()
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerIcon: some View {
        Image(systemName: "calendar.badge.clock")
            .font(.system(size: 60))
            .foregroundStyle(Color.statusInfo)
            .accessibilityIdentifier("pendingChangeIcon")
    }
    
    private var messageContent: some View {
        VStack(spacing: 16) {
            Text(context.headline)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(context.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(context.bulletPoints, id: \.self) { bullet in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.statusSuccess)
                        Text(bullet)
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .background(Color.statusInfo.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("pendingChangeMessage")
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                onSchedule()
                dismiss()
            } label: {
                Text(context.scheduleButtonLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("scheduleForTomorrowButton")
            
            Button {
                showingEmergencyUnlock = true
            } label: {
                Text(String(localized: "I need to unlock now (Emergency)"))
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .accessibilityIdentifier("emergencyUnlockButton")
        }
    }
}

// MARK: - Preview

#Preview {
    PendingGoalChangeView(context: .goalChange()) {
        print("Scheduled for tomorrow")
    } onEmergencyUnlock: {
        print("Emergency unlock confirmed")
    }
}
