//
//  DashboardView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI
import HealthKit

/// The main dashboard view showing the user's progress toward their health goal.
/// Displays step count, loading state, and error handling with retry capability.
///
/// **Why no business logic here?** Following MVVM, the View is purely declarative.
/// All state management and async operations are handled by DashboardViewModel.
struct DashboardView: View {
    
    // MARK: - State
    
    @State private var viewModel: DashboardViewModel
    
    /// Tracks the current scene phase to respond to app lifecycle events.
    /// **Why observe scenePhase?** We need to refresh health data and check the gate
    /// every time the app comes to the foreground. This ensures blocking status stays
    /// in sync with health data even if the user walks outside the app.
    @Environment(\.scenePhase) private var scenePhase
    
    /// Tracks whether to trigger celebration haptic feedback.
    /// Set to true when the user achieves their goal, triggering a success haptic.
    @State private var triggerSuccessHaptic: Bool = false
    
    /// Reference to the scene phase update task for debouncing.
    /// **Why debounce?** Prevents unnecessary API calls during rapid app switching
    /// or multitasking scenarios where the app may foreground/background quickly.
    @State private var scenePhaseTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    /// Creates a DashboardView with the specified ViewModel.
    /// - Parameter viewModel: The ViewModel managing dashboard state.
    init(viewModel: DashboardViewModel) {
        _viewModel = State(initialValue: viewModel)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "Make Hay"))
                .task {
                    await viewModel.onAppear()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    // Cancel any pending scene phase task to debounce rapid changes
                    scenePhaseTask?.cancel()
                    
                    if newPhase == .active {
                        // Debounce with a small delay to handle rapid transitions
                        scenePhaseTask = Task {
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            
                            let previousGoalMet = viewModel.isGoalMet
                            await viewModel.loadGoals()
                            
                            // Trigger haptic if goal was just achieved
                            if !previousGoalMet && viewModel.isGoalMet {
                                triggerSuccessHaptic = true
                            }
                        }
                    }
                }
                .sensoryFeedback(.success, trigger: triggerSuccessHaptic)
        }
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            loadingView
        } else if viewModel.hasError {
            errorView
        } else {
            goalsView
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .accessibilityIdentifier("loadingIndicator")
            
            Text(String(localized: "Loading your goals..."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var goalsView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            goalRings
            
            goalStatusText
            
            if viewModel.isBlocking {
                blockingStatusBadge
            }
            
            Spacer()
            
            refreshButton
        }
        .padding()
        .accessibilityIdentifier("Dashboard.goalsView")
    }
    
    private let ringBaseSize: CGFloat = 240
    private let ringSpacing: CGFloat = 22
    private let ringLineWidth: CGFloat = 18
    
    /// Concentric rings showing progress for each enabled goal.
    private var goalRings: some View {
        ZStack {
            ForEach(Array(viewModel.goalProgresses.enumerated()), id: \.element.id) { index, goal in
                let size = ringBaseSize - (CGFloat(index) * ringSpacing)
                GoalRingView(
                    progress: goal.progress,
                    ringColor: ringColor(for: goal.type),
                    size: size,
                    lineWidth: ringLineWidth,
                    accessibilityId: "goalRing.\(goal.type.rawValue)"
                )
            }
            
            VStack(spacing: 8) {
                if viewModel.isGoalMet {
                    goalMetBadge
                } else if let primaryGoal = viewModel.primaryGoalProgress {
                    primaryGoalDisplay(for: primaryGoal)
                } else {
                    emptyGoalsDisplay
                }
            }
        }
        .frame(width: ringBaseSize, height: ringBaseSize)
        .accessibilityIdentifier("goalRings")
    }
    
    private func ringColor(for type: GoalType) -> Color {
        type.color
    }
    
    private func primaryGoalDisplay(for progress: GoalProgress) -> some View {
        VStack(spacing: 4) {
            Image(systemName: progress.type.iconName)
                .font(.system(size: 32))
                .foregroundStyle(ringColor(for: progress.type))
                .accessibilityIdentifier("dashboardIcon")
            
            Text(formattedCurrentValue(for: progress, includeUnit: false))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .accessibilityIdentifier("primaryGoalValue")
            
            Text(progress.type.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var emptyGoalsDisplay: some View {
        VStack(spacing: 6) {
            Image(systemName: "target")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("emptyGoalsIcon")
            
            Text(String(localized: "Enable a goal"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private func goalSummaryRow(_ progress: GoalProgress) -> some View {
        HStack(spacing: 8) {
            Image(systemName: progress.type.iconName)
                .foregroundStyle(ringColor(for: progress.type))
            
            Text(progress.type.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text("\(formattedCurrentValue(for: progress, includeUnit: true)) / \(formattedTargetValue(for: progress))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("goalSummaryRow.\(progress.type.rawValue)")
    }
    
    private func formattedCurrentValue(for progress: GoalProgress, includeUnit: Bool) -> String {
        switch progress.type {
        case .steps:
            let value = Int(progress.current).formatted(.number)
            return includeUnit ? value + " steps" : value
        case .activeEnergy:
            return Int(progress.current).formatted(.number) + " kcal"
        case .exercise:
            return Int(progress.current).formatted(.number) + " min"
        }
    }
    
    private func formattedTargetValue(for progress: GoalProgress) -> String {
        switch progress.type {
        case .steps:
            return Int(progress.target).formatted(.number) + " steps"
        case .activeEnergy:
            return Int(progress.target).formatted(.number) + " kcal"
        case .exercise:
            return Int(progress.target).formatted(.number) + " min"
        }
    }
    
    /// Celebratory badge shown when the user meets their goal.
    private var goalMetBadge: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.goalExercise)
                .accessibilityIdentifier("goalMetBadge")
            
            Text(String(localized: "Goals Met!"))
                .font(.headline)
                .foregroundStyle(Color.goalExercise)
            
            Text(String(localized: "Apps Unlocked"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    /// Text showing progress as "X / Y steps" below the ring.
    private var goalStatusText: some View {
        VStack(spacing: 4) {
            if viewModel.goalProgresses.isEmpty {
                Text(String(localized: "No goals enabled"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("progressText")
            } else {
                ForEach(viewModel.goalProgresses) { progress in
                    goalSummaryRow(progress)
                }
                
                Text(String(localized: "Unlocks when: \(viewModel.healthGoal.blockingStrategy.displayName)"))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    /// Badge indicating apps are currently blocked.
    /// **Why show this?** Provides clear feedback that the blocking feature is active,
    /// helping users understand why certain apps may be restricted.
    private var blockingStatusBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.caption)
            Text(String(localized: "Apps Blocked"))
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.red.gradient, in: Capsule())
        .accessibilityIdentifier("blockingStatusBadge")
    }
    
    private var refreshButton: some View {
        Button {
            Task {
                await viewModel.loadGoals()
            }
        } label: {
            Label(
                String(localized: "Refresh"),
                systemImage: "arrow.clockwise"
            )
            .font(.headline)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("refreshButton")
    }
    
    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
                .accessibilityIdentifier("errorIcon")
            
            Text(String(localized: "Unable to Load Goals"))
                .font(.title2)
                .fontWeight(.semibold)
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .accessibilityIdentifier("errorMessage")
            }
            
            Button {
                Task {
                    await viewModel.requestAuthorizationAndLoad()
                }
            } label: {
                Text(String(localized: "Retry"))
                    .font(.headline)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("retryButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("Dashboard.errorView")
    }
}

// MARK: - Preview

#Preview("Progress - 50%") {
    let mock = MockHealthService()
    Task { @MainActor in
        await mock.setMockSteps(5_000)
        await mock.setMockActiveEnergy(250)
        await mock.setMockExerciseMinutes(10)
    }
    return DashboardView(viewModel: DashboardViewModel(healthService: mock, blockerService: MockBlockerService()))
}

#Preview("Goal Met") {
    let mock = MockHealthService()
    Task { @MainActor in
        await mock.setMockSteps(12_500)
        await mock.setMockActiveEnergy(650)
        await mock.setMockExerciseMinutes(45)
    }
    return DashboardView(viewModel: DashboardViewModel(healthService: mock, blockerService: MockBlockerService()))
}

#Preview("Loading State") {
    let mock = MockHealthService()
    let viewModel = DashboardViewModel(healthService: mock, blockerService: MockBlockerService())
    return DashboardView(viewModel: viewModel)
}

#Preview("Error State") {
    let viewModel = DashboardViewModel(healthService: ErrorThrowingMockHealthService(), blockerService: MockBlockerService())
    return DashboardView(viewModel: viewModel)
}

// MARK: - Preview Helper

/// A mock that always throws an error for preview purposes.
private actor ErrorThrowingMockHealthService: HealthServiceProtocol {
    var authorizationStatus: HealthAuthorizationStatus { .denied }
    
    func requestAuthorization() async throws {
        throw HealthServiceError.authorizationDenied
    }
    
    func fetchDailySteps() async throws -> Int {
        throw HealthServiceError.authorizationDenied
    }
    
    func fetchActiveEnergy() async throws -> Double {
        throw HealthServiceError.authorizationDenied
    }
    
    func fetchExerciseMinutes(for activityType: HKWorkoutActivityType?) async throws -> Int {
        throw HealthServiceError.authorizationDenied
    }
}
