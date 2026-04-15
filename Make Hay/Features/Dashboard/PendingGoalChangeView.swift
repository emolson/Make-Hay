//
//  PendingGoalChangeView.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/3/26.
//

import SwiftUI

/// Context describing which guarded change flow is being confirmed.
enum PendingChangeContext: Sendable {
    case goalChange
    case blockedAppsChange
    case peekRequest

    var navigationTitle: String {
        switch self {
        case .goalChange:
            return String(localized: "Pause Before Unlocking")
        case .blockedAppsChange:
            return String(localized: "Pause Before Editing")
        case .peekRequest:
            return String(localized: "Mindful Peek")
        }
    }

    var interceptionNavigationTitle: String {
        switch self {
        case .peekRequest:
            return String(localized: "Use Your Daily Peek?")
        default:
            return String(localized: "Hold On")
        }
    }

    var headline: String {
        switch self {
        case .peekRequest:
            return String(localized: "Mindful Peek")
        default:
            return String(localized: "Take a Deep Breath")
        }
    }

    var message: String {
        switch self {
        case .peekRequest:
            return String(
                localized:
                    "You'll have 3 minutes of unrestricted access. This is your only peek today — make it count."
            )
        default:
            return String(
                localized:
                    "Breathe in through your nose and out through your mouth. Think about if unblocking is a need or a want."
            )
        }
    }

    var forfeitWarning: String {
        switch self {
        case .goalChange:
            return String(
                localized:
                    "Emergency unlocks forfeit today's progress. This change will take effect immediately."
            )
        case .blockedAppsChange:
            return String(
                localized:
                    "Emergency unlock applies your blocked-app changes immediately, even before goals are met."
            )
        case .peekRequest:
            return String(
                localized:
                    "This is your only peek today. Your apps will re-lock automatically in 3 minutes."
            )
        }
    }

    var emergencyWarningDescription: String {
        forfeitWarning
    }
}

/// Modal view presented when a user attempts to weaken their guardrails while blocked.
/// It creates a short pause before the emergency unlock path becomes available.
struct PendingGoalChangeView: View {

    private static let breathPhaseDuration: TimeInterval = 4
    private static let breathRounds: Int = 2
    private static let totalDuration: TimeInterval = breathPhaseDuration * Double(breathRounds * 2)
    private static let minimumBreathScale: CGFloat = 0.82
    private static let maximumBreathScale: CGFloat = 1.2

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    /// Tracks whether to show the emergency unlock flow.
    @State private var showingEmergencyUnlock: Bool = false

    /// Start time for the guided breathing cycle.
    @State private var breathingStartDate: Date?

    /// Whether the breathing cycle has finished and the emergency path is available.
    @State private var emergencyUnlockAvailable: Bool = false

    /// The guarded flow context that controls copy/content.
    let context: PendingChangeContext

    /// Callback invoked when the user confirms an emergency unlock.
    let onEmergencyUnlock: () -> Void

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                headerIcon

                countdownRing

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
            .task {
                guard breathingStartDate == nil else { return }
                breathingStartDate = Date()

                try? await Task.sleep(for: .seconds(16))
                guard !Task.isCancelled else { return }
                emergencyUnlockAvailable = true
            }
        }
    }

    // MARK: - View Components

    private var headerIcon: some View {
        Image(systemName: "wind")
            .font(.system(size: 60))
            .foregroundStyle(Color.statusInfo)
            .accessibilityIdentifier("pendingChangeIcon")
    }

    private var countdownRing: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let metrics = breathingMetrics(at: timelineDate(for: context.date))

            ZStack {
                Circle()
                    .stroke(Color.statusInfo.opacity(0.15), lineWidth: 14)

                Circle()
                    .trim(from: 0, to: metrics.progress)
                    .stroke(
                        Color.statusInfo,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text(metrics.instruction)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .textCase(.uppercase)
                    .scaleEffect(metrics.textScale)
                    .frame(width: 180, height: 80)
            }
            .frame(width: 240, height: 240)
            .accessibilityIdentifier("breathingCountdown")
            .accessibilityLabel(String(localized: "Breathing countdown"))
            .accessibilityValue(metrics.accessibilityValue)
        }
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
                .padding(.horizontal)
        }
        .accessibilityIdentifier("pendingChangeMessage")
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if emergencyUnlockAvailable {
                Button {
                    showingEmergencyUnlock = true
                } label: {
                    Text(String(localized: "I Need To Unlock Now"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.statusWarning)
                .controlSize(.large)
                .accessibilityIdentifier("emergencyUnlockButton")
            } else {
                Text(
                    String(
                        localized:
                            "Emergency unlock becomes available when the breathing cycle ends.")
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("emergencyUnlockCountdownHint")
            }
        }
    }

    private func timelineDate(for currentDate: Date) -> Date {
        guard emergencyUnlockAvailable,
            let breathingStartDate
        else {
            return currentDate
        }

        return breathingStartDate.addingTimeInterval(Self.totalDuration)
    }

    private func breathingMetrics(at date: Date) -> BreathingMetrics {
        guard let breathingStartDate else {
            return BreathingMetrics(
                progress: 0,
                instruction: String(localized: "Inhale"),
                textScale: Self.minimumBreathScale,
                accessibilityValue: String(localized: "Inhale, breath 1 of 2")
            )
        }

        let elapsed = min(max(0, date.timeIntervalSince(breathingStartDate)), Self.totalDuration)
        let totalProgress = CGFloat(elapsed / Self.totalDuration)
        let clampedElapsed = min(elapsed, Self.totalDuration - 0.0001)
        let phaseIndex = min(
            Int(clampedElapsed / Self.breathPhaseDuration),
            (Self.breathRounds * 2) - 1
        )
        let phaseElapsed = elapsed - (Double(phaseIndex) * Self.breathPhaseDuration)
        let phaseProgress = min(max(phaseElapsed / Self.breathPhaseDuration, 0), 1)
        let isInhalePhase = phaseIndex.isMultiple(of: 2)
        let instruction = String(localized: isInhalePhase ? "Inhale" : "Exhale")
        let scaleRange = Self.maximumBreathScale - Self.minimumBreathScale
        let textScale =
            isInhalePhase
            ? Self.minimumBreathScale + (scaleRange * phaseProgress)
            : Self.maximumBreathScale - (scaleRange * phaseProgress)
        let breathNumber = min((phaseIndex / 2) + 1, Self.breathRounds)

        return BreathingMetrics(
            progress: totalProgress,
            instruction: instruction,
            textScale: textScale,
            accessibilityValue: "\(instruction), breath \(breathNumber) of \(Self.breathRounds)"
        )
    }
}

private struct BreathingMetrics {
    let progress: CGFloat
    let instruction: String
    let textScale: CGFloat
    let accessibilityValue: String
}

// MARK: - Preview

#Preview {
    PendingGoalChangeView(context: .goalChange) {
    }
}
