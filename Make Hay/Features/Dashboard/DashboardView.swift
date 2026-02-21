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
    
    /// Tracks the goal currently being edited (nil when not editing).
    @State private var editingGoal: GoalProgress?
    
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
                .toolbar {
                    if viewModel.canAddMoreGoals && !viewModel.goalProgresses.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                viewModel.isShowingAddGoal = true
                            } label: {
                                Label(String(localized: "Add Goal"), systemImage: "plus.circle.fill")
                            }
                            .accessibilityIdentifier("addGoalButton")
                        }
                    }
                }
                .sheet(isPresented: $viewModel.isShowingAddGoal) {
                    AddGoalView(viewModel: viewModel)
                }
                .sheet(item: $editingGoal) { goal in
                    editGoalSheet(for: goal)
                }
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
        ScrollView {
            VStack(spacing: 16) {
                // Pending goal change banner
                if viewModel.healthGoal.pendingGoal != nil {
                    pendingChangeBanner
                }
                
                // Inline celebration banner when all goals are met
                if viewModel.isGoalMet {
                    goalMetBanner
                }
                
                if viewModel.goalProgresses.isEmpty {
                    emptyGoalsDisplay
                } else {
                    goalProgressRows
                }
                
                if viewModel.isBlocking {
                    blockingStatusBadge
                }
            }
            .padding()
        }
        .refreshable {
            await viewModel.loadGoals()
        }
        .accessibilityIdentifier("Dashboard.goalsList")
    }
    
    /// Empty state prompting the user to add their first goal.
    /// **Why keep the centered layout?** Maintains the existing friendly
    /// onboarding feel without requiring the bar-based aesthetic.
    private var emptyGoalsDisplay: some View {
        VStack(spacing: 12) {
            Spacer()
                .frame(height: 60)
            
            Image(systemName: "plus.circle.fill")
                .font(.dashboardIcon)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("emptyGoalsIcon")
            
            Text(String(localized: "Add your first goal to start"))
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("progressText")
            
            Button {
                viewModel.isShowingAddGoal = true
            } label: {
                Text(String(localized: "Get Started"))
                    .font(.headline)
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("getStartedButton")
        }
        .padding(.vertical)
    }
    
    /// Vertically stacked linear progress bars, one per enabled goal.
    /// **Why ForEach + GoalProgressRowView?** Each row is self-contained with
    /// its own Gauge, formatting, and accessibility — scales to any goal count.
    private var goalProgressRows: some View {
        VStack(spacing: 4) {
            ForEach(viewModel.goalProgresses) { goal in
                GoalProgressRowView(progress: goal) {
                    editingGoal = goal
                }
            }
            
            // Blocking strategy picker
            blockingStrategyPicker
        }
    }
    
    /// Inline celebration banner shown when all goals are met.
    /// **Why inline instead of overlay?** Keeps the progress bars visible at 100%
    /// so the user can see exactly what they achieved, while clearly communicating
    /// that apps are unlocked.
    private var goalMetBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Goals Met!"))
                    .font(.headline)
                    .foregroundStyle(.green)
                
                Text(String(localized: "Apps Unlocked"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("goalMetBanner")
    }
    
    /// Picker for selecting the blocking strategy (any vs all goals).
    /// **Why here?** The blocking strategy is tightly coupled to goal logic,
    /// so it belongs in the Dashboard near the goals rather than buried in Settings.
    private var blockingStrategyPicker: some View {
        Picker(String(localized: "Unlock when"), selection: Binding(
            get: { viewModel.healthGoal.blockingStrategy },
            set: { newValue in
                Task {
                    await viewModel.updateBlockingStrategy(newValue)
                }
            }
        )) {
            ForEach(BlockingStrategy.allCases) { strategy in
                Text(strategy.displayName).tag(strategy)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 8)
        .accessibilityIdentifier("blockingStrategyPicker")
    }
    
    /// Banner shown when a goal change is scheduled for tomorrow.
    /// **Why show this?** Provides transparency about pending changes and allows cancellation.
    private var pendingChangeBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Goal Update Scheduled"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                if let effectiveDate = viewModel.healthGoal.pendingGoalEffectiveDate {
                    Text("Takes effect at \(effectiveDate, style: .time)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button {
                viewModel.cancelPendingGoal()
            } label: {
                Text(String(localized: "Cancel"))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("cancelPendingButton")
        }
        .padding()
        .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("pendingChangeBanner")
    }
    
    /// Creates an edit sheet for the specified goal progress.
    /// **Why a separate method?** Extracts the complexity of finding the exercise goal
    /// and constructing the proper edit mode from the sheet modifier.
    @ViewBuilder
    private func editGoalSheet(for progress: GoalProgress) -> some View {
        let exerciseGoal: ExerciseGoal? = {
            if progress.type == .exercise, let id = progress.exerciseGoalId {
                return viewModel.healthGoal.exerciseGoals.first { $0.id == id }
            }
            return nil
        }()
        
        NavigationStack {
            GoalConfigurationView(
                viewModel: viewModel,
                goalType: progress.type,
                mode: .edit(exerciseGoalId: progress.exerciseGoalId),
                exerciseGoal: exerciseGoal
            )
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
        .background(Color.statusBlocked.gradient, in: Capsule())
        .accessibilityIdentifier("blockingStatusBadge")
    }
    
    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.dashboardErrorIcon)
                .foregroundStyle(Color.statusWarning)
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

    func fetchCurrentData() async throws -> HealthCurrentData {
        throw HealthServiceError.authorizationDenied
    }
}
