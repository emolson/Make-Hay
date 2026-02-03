//
//  PendingGoalChangeView.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/3/26.
//

import SwiftUI

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
            .navigationTitle(String(localized: "Update Goal?"))
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
                EmergencyUnlockView {
                    onEmergencyUnlock()
                }
            }
        }
    }
    
    // MARK: - View Components
    
    private var headerIcon: some View {
        Image(systemName: "calendar.badge.clock")
            .font(.system(size: 60))
            .foregroundStyle(.blue)
            .accessibilityIdentifier("pendingChangeIcon")
    }
    
    private var messageContent: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Preserve Your Momentum"))
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(String(localized: "You are lowering your target. To preserve your momentum, this change will take effect tomorrow morning."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(localized: "Today's target remains unchanged"))
                        .font(.subheadline)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(localized: "New target starts tomorrow at midnight"))
                        .font(.subheadline)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(localized: "Your progress streak continues"))
                        .font(.subheadline)
                }
            }
            .padding()
            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("pendingChangeMessage")
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                onSchedule()
                dismiss()
            } label: {
                Text(String(localized: "Schedule for Tomorrow"))
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
    PendingGoalChangeView {
        print("Scheduled for tomorrow")
    } onEmergencyUnlock: {
        print("Emergency unlock confirmed")
    }
}
