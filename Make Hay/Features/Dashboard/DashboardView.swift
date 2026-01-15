//
//  DashboardView.swift
//  Make Hay
//
//  Created by Ethan Olson on 12/31/25.
//

import SwiftUI

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
                            await viewModel.loadSteps()
                            
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
            stepsView
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .accessibilityIdentifier("loadingIndicator")
            
            Text(String(localized: "Loading your steps..."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var stepsView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            progressRing
            
            goalStatusText
            
            if viewModel.isBlocking {
                blockingStatusBadge
            }
            
            Spacer()
            
            refreshButton
        }
        .padding()
        .accessibilityIdentifier("Dashboard.stepsView")
    }
    
    /// A circular progress ring showing progress toward the daily step goal.
    /// **Why ZStack for the ring?** We layer a background circle (track) with
    /// a foreground circle (progress) to create the ring effect. The trim
    /// modifier animates based on progress value.
    private var progressRing: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(
                    Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
            
            // Progress arc
            Circle()
                .trim(from: 0, to: viewModel.progress)
                .stroke(
                    progressGradient,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: viewModel.progress)
            
            // Center content
            VStack(spacing: 8) {
                if viewModel.isGoalMet {
                    goalMetBadge
                } else {
                    stepCountDisplay
                }
            }
        }
        .frame(width: 240, height: 240)
        .accessibilityIdentifier("progressRing")
    }
    
    /// The gradient color for the progress ring.
    /// Changes to green when goal is met to provide visual celebration.
    private var progressGradient: AngularGradient {
        if viewModel.isGoalMet {
            return AngularGradient(
                colors: [.green, .mint, .green],
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(360)
            )
        } else {
            return AngularGradient(
                colors: [.blue, .cyan, .blue],
                center: .center,
                startAngle: .degrees(0),
                endAngle: .degrees(360)
            )
        }
    }
    
    /// Display for current step count inside the progress ring.
    private var stepCountDisplay: some View {
        VStack(spacing: 4) {
            Image(systemName: "figure.walk")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
                .accessibilityIdentifier("dashboardIcon")
            
            Text(formattedStepCount)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .accessibilityIdentifier("stepCountLabel")
            
            Text(String(localized: "steps"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    /// Celebratory badge shown when the user meets their goal.
    private var goalMetBadge: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .accessibilityIdentifier("goalMetBadge")
            
            Text(String(localized: "Goal Met!"))
                .font(.headline)
                .foregroundStyle(.green)
            
            Text(formattedStepCount)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .accessibilityIdentifier("stepCountLabel")
        }
    }
    
    /// Text showing progress as "X / Y steps" below the ring.
    private var goalStatusText: some View {
        VStack(spacing: 4) {
            Text(String(localized: "\(formattedStepCount) / \(formattedGoal) steps"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("progressText")
            
            if !viewModel.isGoalMet {
                let remaining = max(0, viewModel.dailyStepGoal - viewModel.currentSteps)
                Text(String(localized: "\(remaining.formatted()) steps to go"))
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
    
    private var formattedStepCount: String {
        viewModel.currentSteps.formatted(.number)
    }
    
    private var formattedGoal: String {
        viewModel.dailyStepGoal.formatted(.number)
    }
    
    private var refreshButton: some View {
        Button {
            Task {
                await viewModel.loadSteps()
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
            
            Text(String(localized: "Unable to Load Steps"))
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
        // Simulate 5000 of 10000 steps
    }
    return DashboardView(viewModel: DashboardViewModel(healthService: mock, blockerService: MockBlockerService()))
}

#Preview("Goal Met") {
    let mock = MockHealthService()
    Task { @MainActor in
        await mock.setMockSteps(12_500)
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
}
