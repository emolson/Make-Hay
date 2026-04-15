//
//  GuardrailInterceptionView.swift
//  Make Hay
//
//  Created by Ethan Olson on 2/3/26.
//

import SwiftUI
import UIKit

/// Modal view presented when a user attempts to weaken their guardrails while blocked.
///
/// The flow uses three deliberate phases to interrupt impulsive bypassing:
/// 1. **Loss Aversion** — Shows current goal progress to highlight what the user is giving up.
/// 2. **Active Pause** — Requires a sustained 15-second press-and-hold that resets on release.
/// 3. **Final Confirmation** — A slide-to-forfeit gesture for conscious, deliberate commitment.
struct GuardrailInterceptionView: View {

    /// Duration (seconds) the user must continuously hold to pass the active-pause phase.
    /// Peek uses a shorter hold (10s) since it doesn't permanently alter goals.
    private var holdDuration: TimeInterval {
        switch context {
        case .peekRequest: return 10
        default: return 15
        }
    }

    /// Phases of the interception flow.
    private enum Phase: Equatable {
        case lossAversion
        case activePause
        case finalConfirmation
    }

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dashboardViewModel) private var viewModel

    // MARK: - State

    /// Current phase of the multi-step interception.
    @State private var phase: Phase = .lossAversion

    /// Timestamp when the current hold gesture began; `nil` when not pressing.
    @State private var holdStartDate: Date?

    /// Gesture state that auto-resets to `false` when the finger lifts.
    @GestureState private var isPressing: Bool = false

    // MARK: - Input

    /// The guarded flow context that controls copy and warning text.
    let context: PendingChangeContext

    /// Callback invoked when the user completes the full bypass flow.
    let onEmergencyUnlock: () -> Void

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                Group {
                    switch phase {
                    case .lossAversion:
                        lossAversionContent
                            .transition(.opacity)
                    case .activePause:
                        activePauseContent
                            .transition(.opacity)
                    case .finalConfirmation:
                        finalConfirmationContent
                            .transition(.opacity)
                    }
                }

                Spacer()

                stayFocusedButton
            }
            .padding()
            .animation(.easeInOut(duration: 0.4), value: phase)
            .navigationTitle(context.interceptionNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("cancelInterceptionButton")
                }
            }
            .task(id: holdStartDate) {
                guard let startDate = holdStartDate else { return }
                await runHoldHaptics(from: startDate)
            }
        }
    }

    // MARK: - Phase 1: Loss Aversion

    private var lossAversionContent: some View {
        VStack(spacing: 24) {
            if let goal = closestUnmetGoal {
                progressRing(for: goal)
            }

            VStack(spacing: 12) {
                Text(progressMessage)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(lossAversionWarningMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .accessibilityIdentifier("lossAversionMessage")

            Button {
                withAnimation {
                    phase = .activePause
                }
            } label: {
                Text(String(localized: "I have an emergency"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("emergencyLink")
        }
    }

    private func progressRing(for goal: GoalProgress) -> some View {
        ZStack {
            Circle()
                .stroke(goal.type.color.opacity(0.15), lineWidth: 14)

            Circle()
                .trim(from: 0, to: goal.progress)
                .stroke(
                    goal.type.color,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text("\(Int(goal.progress * 100))%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))

                Text(goal.type.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 200, height: 200)
        .accessibilityIdentifier("progressRing")
        .accessibilityLabel(progressAccessibilityLabel)
    }

    // MARK: - Phase 2: Active Pause

    private var activePauseContent: some View {
        VStack(spacing: 32) {
            Text(String(localized: "Press and hold to confirm emergency unlock"))
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("holdInstructionText")

            holdCircle

            Text(String(localized: "Release to reset"))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private var holdCircle: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: holdStartDate == nil)) {
            timeline in
            let progress = holdProgress(at: timeline.date)

            ZStack {
                Circle()
                    .stroke(Color.statusWarning.opacity(0.15), lineWidth: 16)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.statusWarning,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 8) {
                    Image(systemName: isPressing ? "hand.tap.fill" : "hand.tap")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.statusWarning)

                    Text(holdTimeRemaining(progress: progress))
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: 220, height: 220)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isPressing) { _, state, _ in
                    state = true
                }
        )
        .onChange(of: isPressing) { _, pressing in
            if pressing {
                holdStartDate = Date()
            } else {
                holdStartDate = nil
            }
        }
        .accessibilityIdentifier("holdToConfirmCircle")
        .accessibilityLabel(String(localized: "Press and hold to confirm"))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    // MARK: - Phase 3: Final Confirmation

    private var finalConfirmationContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(Color.statusWarning)
                .accessibilityIdentifier("forfeitWarningIcon")

            VStack(spacing: 12) {
                Text(String(localized: "Last Step"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(context.forfeitWarning)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .accessibilityIdentifier("forfeitWarningText")

            SlideToForfeitControl(
                label: context == .peekRequest
                    ? String(localized: "Slide to Activate Peek")
                    : String(localized: "Slide to Forfeit and Unlock")
            ) {
                onEmergencyUnlock()
                dismiss()
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Stay Focused Button (persistent across all phases)

    private var stayFocusedButton: some View {
        Button {
            dismiss()
        } label: {
            Text(String(localized: "Stay Focused"))
                .font(.title2.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("stayFocusedButton")
    }

    // MARK: - Progress Helpers

    /// The unmet goal closest to completion, used to maximise loss aversion.
    private var closestUnmetGoal: GoalProgress? {
        viewModel.goalProgresses
            .filter { !$0.isMet }
            .max(by: { $0.progress < $1.progress })
    }

    private var progressMessage: String {
        guard let goal = closestUnmetGoal else {
            return String(localized: "Your goals are already met for today.")
        }
        let remaining = max(0, Int(goal.target - goal.current))
        let formatted = remaining.formatted()
        switch goal.type {
        case .steps:
            return String(
                localized: "You are only \(formatted) steps away from reaching your goal today.")
        case .activeEnergy:
            return String(
                localized: "You are only \(formatted) kcal away from reaching your goal today.")
        case .exercise:
            return String(
                localized:
                    "You are only \(formatted) minutes of exercise away from reaching your goal today."
            )
        case .timeUnlock:
            return String(
                localized: "You are only \(formatted) minutes away from your unlock time.")
        }
    }

    private var lossAversionWarningMessage: String {
        if context == .peekRequest {
            return String(
                localized:
                    "Using your daily peek won't reset your progress, but your apps will re-lock in 3 minutes."
            )
        }
        guard closestUnmetGoal != nil else {
            return String(localized: "Continue only if you still need an immediate override.")
        }
        return String(localized: "Unlocking now forfeits your progress.")
    }

    private var progressAccessibilityLabel: String {
        guard let goal = closestUnmetGoal else {
            return String(localized: "Goal progress")
        }
        return "\(goal.type.displayName), \(Int(goal.progress * 100)) percent complete"
    }

    // MARK: - Hold Helpers

    private func holdProgress(at date: Date) -> CGFloat {
        guard let startDate = holdStartDate else { return 0 }
        let elapsed = date.timeIntervalSince(startDate)
        return min(max(0, elapsed / holdDuration), 1.0)
    }

    private func holdTimeRemaining(progress: CGFloat) -> String {
        let remaining = max(0, Int(ceil(holdDuration * (1.0 - progress))))
        return "\(remaining)s"
    }

    /// Runs escalating haptic feedback for the duration of the hold gesture.
    ///
    /// **Why a task instead of firing in the view body?** Side effects must not
    /// occur during SwiftUI layout. This task runs concurrently while the
    /// gesture is active and cancels automatically when `holdStartDate` changes.
    @MainActor
    private func runHoldHaptics(from startDate: Date) async {
        let light = UIImpactFeedbackGenerator(style: .light)
        let medium = UIImpactFeedbackGenerator(style: .medium)
        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        var lastHapticStep = -1

        light.prepare()
        medium.prepare()
        heavy.prepare()

        while !Task.isCancelled {
            let elapsed = Date().timeIntervalSince(startDate)
            let progress = elapsed / holdDuration

            if progress >= 1.0 {
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
                withAnimation {
                    phase = .finalConfirmation
                }
                return
            }

            let step = Int(progress * 100)
            if step > lastHapticStep {
                lastHapticStep = step

                switch progress {
                case ..<0.3:
                    if step.isMultiple(of: 8) { light.impactOccurred() }
                case 0.3..<0.6:
                    if step.isMultiple(of: 5) { medium.impactOccurred() }
                case 0.6..<0.9:
                    if step.isMultiple(of: 3) { heavy.impactOccurred() }
                default:
                    if step.isMultiple(of: 2) { heavy.impactOccurred(intensity: 1.0) }
                }
            }

            try? await Task.sleep(for: .milliseconds(33))
        }
    }
}

// MARK: - Slide to Forfeit

/// Slide-to-unlock style control requiring a deliberate physical drag to confirm.
///
/// **Why slide instead of tap?** A slide requires sustained, directional intent —
/// it cannot be triggered accidentally or by a mindless tap reflex.
private struct SlideToForfeitControl: View {

    let label: String
    let onComplete: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var completed: Bool = false

    private let thumbSize: CGFloat = 56
    private let trackPadding: CGFloat = 4
    private let completionThreshold: CGFloat = 0.85

    var body: some View {
        GeometryReader { geometry in
            let maxOffset = max(geometry.size.width - thumbSize - (trackPadding * 2), 1)
            let normalizedProgress = min(max(0, dragOffset / maxOffset), 1.0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.surfaceCard)

                Capsule()
                    .fill(Color.statusWarning.opacity(0.2))
                    .frame(width: dragOffset + thumbSize + trackPadding)

                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(1.0 - Double(normalizedProgress)))
                    .frame(maxWidth: .infinity)

                Circle()
                    .fill(Color.statusWarning)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay(
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .offset(x: dragOffset + trackPadding)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !completed else { return }
                                dragOffset = max(0, min(value.translation.width, maxOffset))
                            }
                            .onEnded { _ in
                                guard !completed else { return }
                                if dragOffset / maxOffset >= completionThreshold {
                                    completed = true
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        dragOffset = maxOffset
                                    }
                                    onComplete()
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
            }
        }
        .frame(height: thumbSize + (trackPadding * 2))
        .accessibilityIdentifier("slideToForfeit")
        .accessibilityLabel(label)
        .accessibilityAddTraits(.allowsDirectInteraction)
    }
}

// MARK: - Preview

#Preview("Goal Change") {
    GuardrailInterceptionView(context: .goalChange) {}
}

#Preview("Blocked Apps Change") {
    GuardrailInterceptionView(context: .blockedAppsChange) {}
}

#Preview("Peek Request") {
    GuardrailInterceptionView(context: .peekRequest) {}
}
